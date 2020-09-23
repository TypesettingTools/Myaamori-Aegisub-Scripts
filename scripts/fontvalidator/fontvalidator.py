
import argparse
import collections
import io
import itertools
import logging
import os.path
import pathlib
import re
import sys
import zlib

import ass
import ebmlite
from fontTools.ttLib import ttFont
from fontTools.misc import encodingTools

logging.basicConfig(format="%(name)s: %(message)s")

TAG_PATTERN = re.compile(r"\\\s*([^(\\]+)(?<!\s)\s*(?:\(\s*([^)]+)(?<!\s)\s*)?")
INT_PATTERN = re.compile(r"^[+-]?\d+")
LINE_PATTERN = re.compile(r"(?:\{(?P<tags>[^}]*)\}?)?(?P<text>[^{]*)")

State = collections.namedtuple("State", ["font", "italic", "weight", "drawing"])

def parse_int(s):
    if match := INT_PATTERN.match(s):
        return int(match.group(0))
    else:
        return 0

def parse_tags(s, state, line_style, styles):
    for match in TAG_PATTERN.finditer(s):
        value, paren = match.groups()

        def get_tag(name, *exclude):
            if value.startswith(name) and not any(value.startswith(ex) for ex in exclude):
                args = []
                if paren is not None:
                    args.append(paren)
                if len(stripped := value[len(name):].lstrip()) > 0:
                    args.append(stripped)
                return args
            else:
                return None


        if (args := get_tag("fn")) is not None:
            if len(args) == 0:
                font = line_style.font
            elif args[0].startswith("@"):
                font = args[0][1:]
            else:
                font = args[0]
            state = state._replace(font=font)
        elif (args := get_tag("b", "blur", "be", "bord")) is not None:
            weight = None if len(args) == 0 else parse_int(args[0])
            if weight == 0:
                transformed = 400
            elif weight in (1, -1):
                transformed = 700
            elif 100 <= weight <= 900:
                transformed = weight
            else:
                transformed = None

            state = state._replace(weight=transformed or line_style.weight)
        elif (args := get_tag("i", "iclip")) is not None:
            slant = None if len(args) == 0 else parse_int(args[0])
            state = state._replace(italic=slant == 1 if slant in (0, 1) else line_style.italic)
        elif (args := get_tag("p", "pos", "pbo")) is not None:
            scale = 0 if len(args) == 0 else parse_int(args[0])
            state = state._replace(drawing=scale != 0)
        elif (args := get_tag("r")) is not None:
            if len(args) == 0:
                style = line_style
            else:
                if (style := styles.get(args[0])) is None:
                    print(rf"Warning: \r argument {args[0]} does not exist; defaulting to line style")
                    style = line_style
            state = state._replace(font=style.font, italic=style.italic, weight=style.weight)
        elif (args := get_tag("t")) is not None:
            if len(args) > 0:
                state = parse_tags(args[0], state, line_style, styles)

    return state

def parse_line(line, line_style, styles):
    state = line_style
    for tags, text in LINE_PATTERN.findall(line):
        if len(tags) > 0:
            state = parse_tags(tags, state, line_style, styles)
        if len(text) > 0:
            yield state, text


class Font:
    def __init__(self, fontfile):
        self.fontfile = fontfile
        self.font = ttFont.TTFont(fontfile)
        self.postscript = self.font.has_key("CFF ")
        self.glyphs = self.font.getGlyphSet()

        os2 = self.font["OS/2"]
        self.weight = os2.usWeightClass
        self.italic = os2.fsSelection & 0b1 > 0
        self.slant = self.italic * 110
        self.width = 100

        self.names = [name for name in self.font["name"].names
                      if name.platformID == 3 and name.platEncID in (0, 1)]
        self.family_names = [name.string.decode('utf_16_be')
                             for name in self.names if name.nameID == 1]
        self.full_names = [name.string.decode('utf_16_be')
                           for name in self.names if name.nameID == 4]

        for name in self.font["name"].names:
            if name.nameID == 6 and (encoding := encodingTools.getEncoding(
                    name.platformID, name.platEncID, name.langID)) is not None:
                self.postscript_name = name.string.decode(encoding).strip()

                # these are the two recommended formats, prioritize them
                if (name.platformID, name.platEncID, name.langID) in \
                        [(1, 0, 0), (3, 1, 0x409)]:
                    break

        self.exact_names = [self.postscript_name] if self.postscript else self.full_names

        mac_italic = self.font["head"].macStyle & 0b10 > 0
        if mac_italic != self.italic:
            print(f"warning: different italic values in macStyle and fsSelection for font {self.postscript_name}")

    def missing_glyphs(self, text):
        if (uniTable := self.font.getBestCmap()):
            return [c for c in text
                    if ord(c) not in uniTable]
        elif (symbolTable := self.font["cmap"].getcmap(3, 0)):
            macTable = self.font["cmap"].getcmap(1, 0)
            encoding = encodingTools.getEncoding(1, 0, macTable.language) if macTable else 'mac_roman'
            missing = []
            for c in text:
                try:
                    if (c.encode(encoding)[0] + 0xf000) not in symbolTable.cmap:
                        missing.append(c)
                except UnicodeEncodeError:
                    missing.append(c)
            return missing
        else:
            print(f"warning: could not read glyphs for font {self}")

    def __repr__(self):
        return f"{self.postscript_name}(italic={self.italic}, weight={self.weight})"


class FontCollection:
    def __init__(self, fontfiles):
        self.fonts = []
        for name, f in fontfiles:
            try:
                self.fonts.append(Font(f))
            except Exception as e:
                print(f"Error reading {name}: {e}")

        self.cache = {}
        self.by_full = {name.lower(): font
                        for font in self.fonts
                        for name in font.exact_names}
        self.by_family = {name.lower(): [font for (_, font) in fonts]
                          for name, fonts in itertools.groupby(
                              sorted([(family, font)
                                      for font in self.fonts
                                      for family in font.family_names],
                                     key=lambda x: x[0]),
                              key=lambda x: x[0])}

    def similarity(self, state, font):
        return abs(state.weight - font.weight) + abs(state.italic * 100 - font.slant)

    def _match(self, state):
        if (exact := self.by_full.get(state.font)):
            return exact
        elif (family := self.by_family.get(state.font)):
            return min(family, key=lambda font: self.similarity(state, font))
        else:
            return None

    def match(self, state):
        s = state._replace(font=state.font.lower(), drawing=False)
        try:
            return self.cache[s]
        except KeyError:
            font = self._match(s)
            self.cache[s] = font
            return font


def validate_fonts(doc, fonts, ignore_drawings=False):
    report = {
        "missing_font": collections.defaultdict(set),
        "missing_glyphs": collections.defaultdict(set),
        "missing_glyphs_lines": collections.defaultdict(set),
        "faux_bold": collections.defaultdict(set),
        "faux_italic": collections.defaultdict(set),
        "mismatch_bold": collections.defaultdict(set),
        "mismatch_italic": collections.defaultdict(set)
    }

    styles = {style.name: State(style.fontname, style.italic, 700 if style.bold else 400, False)
              for style in doc.styles}
    for i, line in enumerate(doc.events):
        if isinstance(line, ass.Comment):
            continue
        nline = i + 1

        try:
            style = styles[line.style]
        except KeyError:
            print(f"Warning: Unknown style {line.style} on line {nline}; assuming default style")
            style = State("Arial", False, 400, False)

        for state, text in parse_line(line.text, style, styles):
            font = fonts.match(state)

            if font is None:
                if not (ignore_drawings and state.drawing):
                    report["missing_font"][state.font].add(nline)
                continue

            if state.weight >= font.weight + 150:
                report["faux_bold"][state.font, state.weight, font.weight].add(nline)

            if state.weight <= font.weight - 150:
                report["mismatch_bold"][state.font, state.weight, font.weight].add(nline)

            if state.italic and not font.italic:
                report["faux_italic"][state.font].add(nline)

            if not state.italic and font.italic:
                report["mismatch_italic"][state.font].add(nline)

            if not state.drawing:
                missing = font.missing_glyphs(text)
                report["missing_glyphs"][state.font].update(missing)
                if len(missing) > 0:
                    report["missing_glyphs_lines"][state.font].add(nline)

    issues = 0

    def format_lines(lines, limit=10):
        sorted_lines = sorted(lines)
        if len(sorted_lines) > limit:
            sorted_lines = sorted_lines[:limit]
            sorted_lines.append("[...]")
        return ' '.join(map(str, sorted_lines))

    for font, lines in sorted(report["missing_font"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Could not find font {font} on line(s): {format_lines(lines)}")

    for (font, reqweight, realweight), lines in sorted(report["faux_bold"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Faux bold used for font {font} (requested weight {reqweight}, got {realweight}) " \
              f"on line(s): {format_lines(lines)}")

    for font, lines in sorted(report["faux_italic"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Faux italic used for font {font} on line(s): {format_lines(lines)}")

    for (font, reqweight, realweight), lines in sorted(report["mismatch_bold"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Requested weight {reqweight} but got {realweight} for font {font} " \
              f"on line(s): {format_lines(lines)}")

    for font, lines in sorted(report["mismatch_italic"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Requested non-italic but got italic for font {font} on line(s): " + \
              format_lines(lines))

    for font, lines in sorted(report["missing_glyphs_lines"].items(), key=lambda x: x[0]):
        issues += 1
        print(f"- Font {font} is missing glyphs {''.join(sorted(report['missing_glyphs'][font]))} " \
              f"on line(s): {format_lines(lines)}")

    print(f"{issues} issue(s) found")
    return issues > 0



def get_element(parent, element, id=False):
    return next(get_elements(parent, element, id=id))

def get_elements(parent, *element, id=False):
    if id:
        return filter(lambda x: x.id in element, parent)
    else:
        return filter(lambda x: x.name in element, parent)

def get_dicts(parent, element, id=False):
    return ({x.name: x for x in elem} for elem in get_elements(parent, element, id=id))


def get_subtitles(mkv):
    subtitles = []

    for segment in get_elements(mkv, "Segment"):
        tracks_to_read = {}
        tracks = get_element(segment, "Tracks")
        for track in get_dicts(tracks, "TrackEntry"):
            if track["CodecID"].value != b'S_TEXT/ASS':
                continue

            compression = False
            for encoding in get_elements(track.get("ContentEncodings", []), "ContentEncoding"):
                for compression in get_elements(encoding, "ContentCompression"):
                    compression = True

            try:
                track_name = track["Name"].value
            except KeyError:
                track_name = "Unknown"

            assdoc = ass.parse(io.TextIOWrapper(io.BytesIO(track["CodecPrivate"].value),
                                                encoding='utf_8_sig'))
            tracks_to_read[track["TrackNumber"].value] = track_name, assdoc, compression

        track_lines = {k: {} for k in tracks_to_read}
        for cluster in get_elements(segment, "Cluster"):
            for elem in cluster:
                if elem.name == "SimpleBlock":
                    block = elem.value
                elif elem.name == "BlockGroup":
                    block = get_element(elem, 0xa1, id=True).value
                else:
                    continue

                stream = io.BytesIO(block)
                track, _ = ebmlite.decoding.readElementSize(stream)
                if track in tracks_to_read:
                    _, _, compression = tracks_to_read[track]

                    timestamp = ebmlite.decoding.readInt(stream, 2)
                    stream.read(1)

                    data = stream.read()
                    if compression:
                        data = zlib.decompress(data)

                    order, layer, line = data.split(b',', 2)
                    timestamp = b'0:00:00.00,0:00:00.00'
                    track_lines[track][int(order)] = b'Dialogue: ' + layer + b',' + timestamp + b',' + line

        for track_id, l in track_lines.items():
            name, assdoc, _ = tracks_to_read[track_id]
            lines = b'[Events]\n' + b'\n'.join([l[k] for k in sorted(l)])
            events = ass.parse(io.TextIOWrapper(io.BytesIO(lines), encoding='utf_8_sig'))
            assdoc.events.extend(events.events)
            subtitles.append((name, assdoc))

    return subtitles


# from mpv
FONT_MIMETYPES = {
    b"application/x-truetype-font",
    b"application/vnd.ms-opentype",
    b"application/x-font-ttf",
    b"application/x-font",
    b"application/font-sfnt",
    b"font/collection",
    b"font/otf",
    b"font/sfnt",
    b"font/ttf"
}

def get_fonts(mkv):
    fonts = []

    for segment in get_elements(mkv, "Segment"):
        for attachments in get_elements(segment, "Attachments"):
            for attachment in get_dicts(attachments, "AttachedFile"):
                if attachment["FileMimeType"].value not in FONT_MIMETYPES:
                    print(f"Ignoring non-font attachment {attachment['FileName'].value}")

                fonts.append((attachment["FileName"].value,
                              io.BytesIO(attachment["FileData"].value)))

    return fonts

def is_mkv(filename):
    with open(filename, 'rb') as f:
        return f.read(4) == b'\x1a\x45\xdf\xa3'

def main():
    parser = argparse.ArgumentParser(
        description="Validate font usage in a muxed Matroska file or an ASS file.")
    parser.add_argument('subtitles', help="""
File containing the subtitles to verify. May be a Matroska file or an ASS file.
If a Matroska file is provided, any attached fonts will be used.
""")
    parser.add_argument('additional_fonts', nargs='*', help="""
List of additional fonts to use for verification.
May be a Matroska file with fonts attached, a directory containing font files, or a single font file.
""")
    parser.add_argument('--ignore-drawings', action='store_true', default=False,
                        help="Don't warn about missing fonts only used for drawings.")
    args = parser.parse_args()

    schema = ebmlite.loadSchema("matroska.xml")

    if is_mkv(args.subtitles):
        mkv = schema.load(args.subtitles)
        subtitles = get_subtitles(mkv)
        fontlist = get_fonts(mkv)
    else:
        with open(args.subtitles, 'r', encoding='utf_8_sig') as f:
            subtitles = [(os.path.basename(args.subtitles), ass.parse(f))]
        fontlist = []

    for additional_fonts in args.additional_fonts:
        path = pathlib.Path(additional_fonts)
        if path.is_dir():
            fontlist.extend((p.name, str(p)) for p in path.iterdir() if p.is_file())
        elif is_mkv(additional_fonts):
            fontmkv = schema.load(additional_fonts)
            fontlist.extend(get_fonts(fontmkv))
        else:
            fontlist.append((path.name, additional_fonts))

    issues = False
    fonts = FontCollection(fontlist)
    for name, doc in subtitles:
        print(f"Validating track {name}")
        issues = issues or validate_fonts(doc, fonts, args.ignore_drawings)

    return issues

if __name__ == "__main__":
    sys.exit(main())

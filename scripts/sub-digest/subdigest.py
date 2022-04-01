
from __future__ import annotations
import argparse
import codecs
import collections
import datetime
import inspect
import io
import logging
import pathlib
import re
import sys
import warnings

import ass

_filter_groups = []

def filter_group(cls):
    _filter_groups.append(cls)
    return cls

def filter(f):
    f._filter = True
    return f

def action_factory(types):
    class ParseChain(argparse.Action):

        def __call__(self, parser, namespace, values, option_string=None):
            if not hasattr(namespace, "chain"):
                setattr(namespace, "chain", [])

            vals = []
            for typ, val in zip(types, values):
                if isinstance(typ, set):
                    if val not in typ:
                        raise argparse.ArgumentTypeError(
                            f"Argument '{val}' to option {option_string} "
                            f"not among allowed values {typ}")
                    vals.append(val)
                else:
                    try:
                        val = typ(val)
                        vals.append(val)
                    except ValueError:
                        raise argparse.ArgumentTypeError(
                            f"Argument '{val}' to option {option_string} "
                            f"not of expected type {typ.__name__}")

            namespace.chain.append((self.dest, vals))

    return ParseChain

def generate_argument(group, f):
    flag_name = '--' + f.__name__.replace('_', '-')
    sig = inspect.signature(f)

    return_type = sig.return_annotation
    doc = f"Output type: {return_type}."
    if f.__doc__ is not None:
        doc = f"{f.__doc__} {doc}"

    parameters = list(sig.parameters.items())[1:]
    assert all(param.kind == inspect.Parameter.POSITIONAL_OR_KEYWORD
               for _, param in parameters), f"Non-positional argument in {f.__name__}"
    if len(parameters) == 1 and parameters[0][1].default is not inspect.Parameter.empty:
        nargs = "?"
        default = parameters[0][1].default
    else:
        nargs = len(parameters)
        default = None

    types = [eval(param.annotation, globals(), locals()) for _, param in parameters]

    metavar = tuple(f"{{{','.join(typ)}}}" if isinstance(typ, set) else name.upper()
                       for typ, (name, _) in zip(types, parameters))

    group.add_argument(flag_name, nargs=nargs, default=default, help=doc,
                       metavar=metavar, action=action_factory(types))

@filter_group
class Subtitles:

    def __init__(self, sub_file, filename):
        self.sub_file = sub_file
        self.filename = filename
        self.section = "events"
        self.selection_clear()
        self._fps = 24000 / 1001
        self._ms_count = 0
        self._ms_files = {}

        self._helpers = {
            "secs": lambda t: datetime.timedelta(seconds=t),
            "mins": lambda t: datetime.timedelta(minutes=t),
            "millis": lambda t: datetime.timedelta(milliseconds=t),
            "frames": lambda t: datetime.timedelta(seconds=t / self._fps)
        }

    def _set_section(self, lines):
        setattr(self.sub_file, self.section, lines)

    def _get_section(self):
        return getattr(self.sub_file, self.section)

    def _find_matching_lines(self, field, pattern):
        selection = {i for i, line in enumerate(self._get_section())
                     if re.search(pattern, getattr(line, field))}
        return selection

    def _find_line_expr(self, expr):
        expr_c = compile(expr, '<string>', 'eval')
        selection = {i for i, line in enumerate(self._get_section())
                     if eval(expr_c, None, {"_": line, **self._helpers})}
        return selection

    def _get_selection(self):
        if self.selection is None:
            # return copy of section contents as list
            return [line for line in self._get_section()]

        return [line for i, line in enumerate(self._get_section())
                if i in self.selection]

    def _get_nonselection(self):
        if self.selection is None:
            return []

        return [line for i, line in enumerate(self._get_section())
                if i not in self.selection]

    def _process_selection(self, f):
        lines = self._get_selection()

        if self.selection is None:
            indices = [i for i, line in enumerate(lines)]
        else:
            indices = sorted(self.selection)

        f(lines)
        section = self._get_section()
        for i, line in zip(indices, lines):
            section[i] = line

    @filter
    def use_styles(self) -> Subtitles:
        """Set the current section to the styles section."""
        self.section = "styles"
        self.selection_clear()
        return self

    @filter
    def use_events(self) -> Subtitles:
        """Set the current section to the events section."""
        self.section = "events"
        self.selection_clear()
        return self

    def _set_selection(self, lines):
        self.selection = lines

    def _add_selection(self, lines):
        # if None, already covers all lines (implicitly), nothing to add
        if self.selection is not None:
            self.selection = self.selection | lines

    def _subtract_selection(self, lines):
        cur_selection = (self.selection if self.selection is not None
                         else set(range(len(self._get_section()))))
        self.selection = cur_selection - lines

    def _intersect_selection(self, lines):
        if self.selection is None:
            self.selection = lines
        else:
            self.selection = self.selection & lines


    @filter
    def selection_set(self, field: str, pattern: str) -> Subtitles:
        """Set the selection to all lines in the current section
        for which the given field matches the given regex pattern."""
        self._set_selection(self._find_matching_lines(field, pattern))
        return self

    @filter
    def selection_add(self, field: str, pattern: str) -> Subtitles:
        """Set the selection to the union of the current selection
        and all lines in the current section for which the given
        field matches the given regex pattern."""
        self._add_selection(self._find_matching_lines(field, pattern))
        return self

    @filter
    def selection_subtract(self, field: str, pattern: str) -> Subtitles:
        """Set the selection to the current selection, minus all lines
        in the current section for which the given field matches
        the given regex pattern."""
        self._subtract_selection(self._find_matching_lines(field, pattern))
        return self

    @filter
    def selection_intersect(self, field: str, pattern: str) -> Subtitles:
        """Set the selection to the intersection of the current selection
        and all lines in the current section for which the given field
        matches the given regex pattern."""
        self._intersect_selection(self._find_matching_lines(field, pattern))
        return self

    @filter
    def selection_set_expr(self, expr: str) -> Subtitles:
        """Set the selection to the lines in the current section for which
        expr returns true."""
        self._set_selection(self._find_line_expr(expr))
        return self

    @filter
    def selection_add_expr(self, expr: str) -> Subtitles:
        """Set the selection to the union of the current selection
        and all lines in the current section for which
        expr returns true."""
        self._add_selection(self._find_line_expr(expr))
        return self

    @filter
    def selection_subtract_expr(self, expr: str) -> Subtitles:
        """Set the selection to the current selection, minus all lines
        in the current section for which expr returns true."""
        self._subtract_selection(self._find_line_expr(expr))
        return self

    @filter
    def selection_intersect_expr(self, expr: str) -> Subtitles:
        """Set the selection to the intersection of the current selection
        and all lines in the current section for which expr returns true."""
        self._intersect_selection(self._find_line_expr(expr))
        return self

    @filter
    def selection_clear(self) -> Subtitles:
        """Reset the selection (select all lines)."""
        self.selection = None
        return self

    @filter
    def keep_selected(self) -> Subtitles:
        """Remove all lines not in the current selection. Clears the selection."""
        self._set_section(self._get_selection())
        self.selection_clear()
        return self

    @filter
    def remove_selected(self) -> Subtitles:
        """Remove all lines in the current selection. Clears the selection."""
        self._set_section(self._get_nonselection())
        self.selection_clear()
        return self

    @filter
    def move_selected(self, position: {"TOP", "BOTTOM"}) -> Subtitles:
        """Move all selected lines to the top or bottom of the current section."""
        selection = self._get_selection()
        nonselection = self._get_nonselection()
        if position == "TOP":
            self._set_section(selection + nonselection)
            self.selection = set(range(len(selection)))
        else:
            self._set_section(nonselection + selection)
            self.selection = set(range(len(nonselection), len(nonselection) + len(selection)))
        return self

    @filter
    def merge_file(self, other_file: argparse.FileType(encoding='utf-8-sig')) -> Subtitles:
        """Append the styles and event lines from another file."""
        f = ass.parse(other_file)
        self.sub_file.events.extend(f.events)
        existing_styles = {style.name: style.dump() for style in self.sub_file.styles}
        for style in f.styles:
            if style.name in existing_styles and style.dump() != existing_styles[style.name]:
                print(f"Warning: Ignoring style {style.name} from "
                      f"{other_file.name}.", file=sys.stderr)
                continue
            self.sub_file.styles.append(style)
        return self

    def _import_file(self, imp_definition, styles, events, fields):
        # strip extradata info
        fname = re.sub(r"^\{=\d+(,\d+)*\}", "", imp_definition.text)
        shifted = imp_definition.effect == 'import-shifted'

        self._ms_count += 1
        self._ms_files[self._ms_count] = fname

        path = pathlib.Path(self.filename).parent / fname
        with path.open(encoding='utf-8-sig') as f:
            imp = ass.parse(f)

        if shifted:
            try:
                sync_line = next(line for line in imp.events
                                 if line.effect == 'sync')
            except StopIteration:
                raise ValueError(f"No sync line in {fname}")

            time_diff = imp_definition.start - sync_line.start

            for line in imp.events:
                line.start += time_diff
                line.end += time_diff

        for line in imp.events:
            line.layer += imp_definition.layer
            line.style = f"{self._ms_count}${line.style}"
            events.append(line)

        for style in imp.styles:
            style.name = f"{self._ms_count}${style.name}"
            styles[style.name] = style

        for field, value in imp.fields.items():
            if field in fields and fields[field] != value:
                logging.warning(f"Ignoring conflicting value {value} for {field} from {fname}")
            else:
                fields[field] = value

    def _import_files(self, field=None, pattern=None):
        if self.filename is None:
            raise ValueError("Cannot import when reading from stdin")

        styles = collections.OrderedDict((style.name, style)
                                         for style in self.sub_file.styles
                                         if not re.match(r'\d+\$', style.name))
        events = []
        fields = {}

        for line in self.sub_file.events:
            if re.match(r'\d+\$', line.style):
                continue
            if line.effect in ('import', 'import-shifted') and \
                    (field is None or re.search(pattern, getattr(line, field))):
                self._import_file(line, styles, events, fields)
            else:
                events.append(line)

        self.sub_file.events = events
        self.sub_file.styles = list(styles.values())
        self.sub_file.fields = fields

    @filter
    def ms_import(self) -> Subtitles:
        """Import files according to import definitions in a file using Merge Scripts syntax.
        Discards styles and lines already imported from external files.
        Imported styles will be prefixed by a namespace identifier, e.g. 1$Default."""
        self.ms_import_filter(None, None)
        return self

    @filter
    def ms_import_filter(self, field: str, pattern: str) -> Subtitles:
        """Import files according to import definitions in a file using Merge Scripts syntax.
        Discards styles and lines already imported from external files.
        Imported styles will be prefixed by a namespace identifier, e.g. 1$Default.
        Only import files corresponding to import definitions matching the given pattern."""
        self._import_files(field, pattern)
        return self

    @filter
    def ms_remove_namespace(self) -> Subtitles:
        """Remove namespace identifiers from style names (e.g. change 1$Default to Default)."""
        styles = collections.OrderedDict()
        for style in self.sub_file.styles:
            num, style.name = re.match(r"^(?:(\d+)\$)?(.*)", style.name).groups()

            if style.name in styles:
                if styles[style.name].dump() != style.dump():
                    fname = self._ms_files[int(num)] if num is not None else self.filename
                    logging.warning(f"Ignoring conflicting style {style.name} from {fname}")
            else:
                styles[style.name] = style

        self.sub_file.styles = list(styles.values())

        for line in self.sub_file.events:
            line.style = re.sub(r"^\d+\$", "", line.style)

        return self

    @filter
    def ms_import_rc(self) -> Subtitles:
        """Equivalent to --ms-import --remove-comments --remove-unused-styles
        --ms-remove-namespace."""
        self.ms_import_rc_filter(None, None)
        return self

    @filter
    def ms_import_rc_filter(self, field: str, pattern: str) -> Subtitles:
        """Equivalent to --ms-import-filter FIELD PATTERN --remove-comments --remove-unused-styles
        --ms-remove-namespace."""
        self.ms_import_filter(field, pattern)
        self.remove_comments()
        self.remove_unused_styles()
        self.ms_remove_namespace()
        return self

    @filter
    def sort_field(self, field: str, order: {"ASC", "DESC"}) -> Subtitles:
        """Sort all lines in the current selection based on the given field,
        either ascending or descending."""
        def _sort(events):
            events.sort(key=lambda line: getattr(line, field), reverse=order == "DESC")
        self._process_selection(_sort)
        return self

    @filter
    def sort_expr(self, expr: str, order: {"ASC", "DESC"}) -> Subtitles:
        """Sort all lines in the current selection based on the return value of expr,
        either ascending or descending."""
        def _sort(events):
            expr_c = compile(expr, '<string>', 'eval')
            events.sort(key=lambda line: eval(expr_c, None, {"_": line, **self._helpers}),
                        reverse=order == "DESC")
            return events
        self._process_selection(_sort)
        return self

    @filter
    def modify_field(self, field: str, pattern: str, replace: str) -> Subtitles:
        """Replace occurrences of pattern with the given replacement string
        in the given field on all lines in the current selection.
        Accepts regular expressions."""
        def _modify(lines):
            pattern_c = re.compile(pattern)
            for line in lines:
                cur_val = getattr(line, field)
                val = pattern_c.sub(replace, cur_val)
                setattr(line, field, val)
        self._process_selection(_modify)
        return self

    @filter
    def modify_expr(self, field: str, expr: str) -> Subtitles:
        """Replace the value of the given field on all lines in the selection
        with the result of the given expression."""
        def _modify(lines):
            expr_c = compile(expr, '<string>', 'eval')
            for line in lines:
                cur_val = getattr(line, field)
                val = eval(expr_c, None, {"_": line, **self._helpers})
                setattr(line, field, val)
        self._process_selection(_modify)
        return self

    @filter
    def shift(self, expr: str) -> Subtitles:
        """Shifts the start and end time by a specified amount.
        Example: --shift "secs(-10)".
        """
        expr_c = compile(expr, '<string>', 'eval')
        def _modify(lines):
            for line in lines:
                time = eval(expr_c, None, {"_": line, **self._helpers})
                line.start += time
                line.end += time
        self._process_selection(_modify)
        return self

    @filter
    def remove_all_tags(self) -> Subtitles:
        """Remove all tags (everything in the text field enclosed in {})
        from all dialogue lines. No-op if current section is not
        the events section."""
        if self.section == "events":
            self.modify_field("text", "{[^}]+}", "")
        return self

    @filter
    def remove_unused_styles(self) -> Subtitles:
        """Remove all styles not used in any dialogue lines.
        Clears the selection if the current section is the styles section."""
        used_styles = {line.style for line in self.sub_file.events}
        self.sub_file.styles = [style for style in self.sub_file.styles
                                if style.name in used_styles]
        if self.section == "styles":
            self.selection_clear()
        return self

    @filter
    def remove_comments(self) -> Subtitles:
        """Removes all commented lines in current selection.
        Clears the selection if the current selection is the events section."""
        self.sub_file.events = [event for event in self.sub_file.events
                                if event.TYPE != "Comment"]
        if self.section == "events":
            self.selection_clear()
        return self

    @filter
    def get_field(self, field: str) -> Text:
        """Returns the given field from all lines in the current selection as text,
        newline separated."""
        selection = self._get_selection()
        return Text("".join(str(getattr(line, field)) + "\n" for line in selection))

    @filter
    def fps(self, fps: str) -> Subtitles:
        """Set the fps to use for the frames() function. Default is 24000/1001."""
        self._fps = eval(fps)
        return self

    @filter
    def set_script_info(self, field: str, value: str) -> Subtitles:
        self.sub_file.fields[field] = value
        return self

    def __str__(self):
        sio = io.StringIO()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            self.sub_file.dump_file(sio)
        return sio.getvalue()

    def __getattr__(self, name):
        return getattr(self.sub_file, name)

@filter_group
class Text:

    def __init__(self, text):
        self.text = text

    def __str__(self):
        return self.text

def main():
    parser = argparse.ArgumentParser()

    for group in _filter_groups:
        arggroup = parser.add_argument_group(group.__name__)
        for name, member in inspect.getmembers(group):
            if getattr(member, '_filter', False):
                generate_argument(arggroup, member)

    parser.add_argument("-i", "--input", help="Specify input file (default: stdin)")
    parser.add_argument("-o", "--output", help="Specify output file (default: stdout)")
    parser.add_argument("--in-place", action="store_true", help="Perform operations in place")
    args = parser.parse_args()

    if args.input is None or args.input == '-':
        filename = None
        sub_obj = ass.parse(codecs.getreader('utf-8-sig')(sys.stdin.buffer))
    else:
        filename = args.input
        with open(args.input, 'r', encoding='utf-8-sig') as f:
            sub_obj = ass.parse(f)

    sub_obj = Subtitles(sub_obj, filename)

    for func, filter_args in getattr(args, 'chain', []):
        filt = getattr(sub_obj, func)
        sub_obj = filt(*filter_args)

    if args.in_place and args.input is not None:
        args.output = args.input

    if args.output is None or args.output == '-':
        sys.stdout.buffer.write(str(sub_obj).encode('utf-8-sig'))
    else:
        with open(args.output, 'w', encoding="utf-8-sig") as f:
            f.write(str(sub_obj))

if __name__ == '__main__':
    sys.exit(main())

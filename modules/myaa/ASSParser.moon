DependencyControl = require "l0.DependencyControl"

version = DependencyControl {
    name: "ASSParser",
    version: "0.0.4",
    description: "Utility function for parsing ASS files",
    author: "Myaamori",
    url: "http://github.com/TypesettingTools/Myaamori-Aegisub-Scripts",
    moduleName: "myaa.ASSParser",
    feed: "https://raw.githubusercontent.com/TypesettingTools/Myaamori-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.re", "aegisub.util",
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
    }
}

re, util, F = version\requireModules!

import lshift, rshift, band, bor from bit

parser = {}

STYLE_FORMAT_STRING = "Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, " ..
        "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, " ..
        "Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, " ..
        "MarginV, Encoding"
EVENT_FORMAT_STRING = "Layer, Start, End, Style, Name, MarginL, MarginR, " ..
        "MarginV, Effect, Text"
DATA_FORMAT_STRING = "Id, Key, Value"

DIALOGUE_DEFAULTS =
    actor: "", class: "dialogue", comment: false, effect: "",
    start_time: 0, end_time: 0, layer: 0, margin_l: 0,
    margin_r: 0, margin_t: 0, section: "[Events]", style: "Default",
    text: "", extra: nil

STYLE_DEFAULTS =
    class: "style", section: "[V4+ Styles]", name: "Default",
    fontname: "Arial", fontsize: 45, color1: "&H00FFFFFF",
    color2: "&H000000FF", color3: "&H00000000", color4: "&H00000000",
    bold: false, italic: false, underline: false, strikeout: false,
    scale_x: 100, scale_y: 100, spacing: 0, angle: 0,
    borderstyle: 1, outline: 4.5, shadow: 4.5, align: 2,
    margin_l: 23, margin_r: 23, margin_t: 23, encoding: 1

create_line_from = (line, fields)->
    line = util.copy line
    if fields
        for key, value in pairs fields
            line[key] = value
    return line

parser.create_dialogue_line = (fields)->
    line = create_line_from DIALOGUE_DEFAULTS, fields
    line.extra = line.extra or {}
    line

parser.create_style_line = (fields)-> create_line_from STYLE_DEFAULTS, fields

parser.decode_extradata_value = (value)->
    enc, data = value\match "^([eu])(.*)$"

    if enc == 'e'
        return parser.inline_string_decode data
    else
        return parser.uudecode data

parse_format_line = (format_string)-> [match for match in format_string\gmatch "([^, ]+)"]

parser.raw_to_line = (raw, extradata=nil, format=nil)->
    line_type, value = raw\match "^([^:]+):%s*(.*)$"
    if not value
        return nil

    default_format = {Dialogue: EVENT_FORMAT_STRING,
                      Comment: EVENT_FORMAT_STRING,
                      Style: STYLE_FORMAT_STRING,
                      Data: DATA_FORMAT_STRING}

    if line_type == "Format"
        return {class: "format", format: parse_format_line value}
    elseif not default_format[line_type]
        return {class: "info", key: line_type, value: value}

    format = format or parse_format_line default_format[line_type]
    elements = F.string.split value, ",", 1, true, #format - 1
    return nil if #elements != #format

    fields = {format[i], elements[i] for i=1,#elements}

    if line_type == "Dialogue" or line_type == "Comment"
        line = parser.create_dialogue_line
            actor: fields.Name, comment: line_type == "Comment"
            effect: fields.Effect, start_time: F.util.assTimecode2ms(fields.Start)
            end_time: F.util.assTimecode2ms(fields.End), layer: tonumber(fields.Layer)
            margin_l: tonumber(fields.MarginL), margin_r: tonumber(fields.MarginR)
            margin_t: tonumber(fields.MarginV), style: fields.Style
            text: fields.Text

        -- handle extradata (e.g. '{=32=33}Line text')
        extramatch = re.match line.text, "^\\{((?:=\\d+)+)\\}(.*)$"
        if extramatch
            line.text = extramatch[3].str
            if extradata
                for id in extramatch[2].str\gmatch "=(%d+)"
                    id = tonumber id
                    if extradata[id]
                        eline = extradata[id]
                        line.extra[eline.key] = eline.value
            else
                aegisub.log 2,
                    "WARNING: Found extradata ID, but no extradata mapping provided: " ..
                    "#{raw}\n"

        return line
    elseif line_type == "Style"
        boolean_map = {["-1"]: true, ["0"]: false}
        line = parser.create_style_line
            name: fields.Name, fontname: fields.Fontname
            fontsize: tonumber(fields.Fontsize), color1: fields.PrimaryColour
            color2: fields.SecondaryColour, color3: fields.OutlineColour
            color4: fields.BackColour, bold: boolean_map[fields.Bold]
            italic: boolean_map[fields.Italic], underline: boolean_map[fields.Underline]
            strikeout: boolean_map[fields.StrikeOut], scale_x: tonumber(fields.ScaleX)
            scale_y: tonumber(fields.ScaleY), spacing: tonumber(fields.Spacing)
            angle: tonumber(fields.Angle), borderstyle: tonumber(fields.BorderStyle)
            outline: tonumber(fields.Outline), shadow: tonumber(fields.Shadow)
            align: tonumber(fields.Alignment), margin_l: tonumber(fields.MarginL)
            margin_r: tonumber(fields.MarginR), margin_t: tonumber(fields.MarginV)
            encoding: tonumber(fields.Encoding)

        return line
    elseif line_type == "Data"
        return {class: "data", id: tonumber(fields.Id),
                key: fields.Key, value: parser.decode_extradata_value fields.Value}

parser.line_to_raw = (line)->
    if line.class == "dialogue"
        prefix = if line.comment then "Comment" else "Dialogue"
        "#{prefix}: #{line.layer},#{F.util.ms2AssTimecode line.start_time}," ..
            "#{F.util.ms2AssTimecode line.end_time},#{line.style},#{line.actor}," ..
            "#{line.margin_l},#{line.margin_r},#{line.margin_t},#{line.effect},#{line.text}"
    elseif line.class == "style"
        map = {[true]: "-1", [false]: "0"}
        clr = (color)-> util.ass_style_color util.extract_color color
        "Style: #{line.name},#{line.fontname},#{line.fontsize},#{clr line.color1}," ..
            "#{clr line.color2},#{clr line.color3},#{clr line.color4},#{map[line.bold]}," ..
            "#{map[line.italic]},#{map[line.underline]},#{map[line.strikeout]}," ..
            "#{line.scale_x},#{line.scale_y},#{line.spacing},#{line.angle}," ..
            "#{line.borderstyle},#{line.outline},#{line.shadow},#{line.align}," ..
            "#{line.margin_l},#{line.margin_r},#{line.margin_t},#{line.encoding}"
    elseif line.class == "info"
        "#{line.key}: #{line.value}"

parser.inline_string_encode = (input)->
    output = {}
    for i=1,#input
        c = input\byte i
        if c <= 0x1F or c >= 0x80 or c == 0x23 or c == 0x2C or c == 0x3A or c == 0x7C
            table.insert output, string.format "#%02X", c
        else
            table.insert output, input\sub i,i
    return table.concat output

parser.inline_string_decode = (input)->
    output = {}
    i = 1
    while i <= #input
        if (input\sub i, i) != "#" or i + 1 > #input
            table.insert output, input\sub i, i
        else
            table.insert output, string.char tonumber (input\sub i+1, i+2), 16
            i += 2
        i += 1
    return table.concat output

parser.uuencode = (input)->
    ret = {}
    for pos=1,#input,3
        chunk = input\sub pos, pos+2
        src = [c\byte! for c in chunk\gmatch "."]
        while #src < 3
            src[#src+1] = 0

        dst = {(rshift src[1], 2),
               (bor (lshift (band src[1], 0x3), 4), (rshift (band src[2], 0xF0), 4)),
               (bor (lshift (band src[2], 0xF), 2), (rshift (band src[3], 0xC0), 6)),
               (band src[3], 0x3F)}

        for i=1,math.min(#input - pos + 2, 4)
            table.insert ret, dst[i] + 33

    return table.concat [string.char i for i in *ret]

parser.uudecode = (input)->
    ret = {}
    pos = 1

    while pos <= #input
        chunk = input\sub pos, pos+3
        src = [(string.byte c) - 33 for c in chunk\gmatch "."]
        if #src > 1
            table.insert ret, bor (lshift src[1], 2), (rshift src[2], 4)
        if #src > 2
            table.insert ret, bor (lshift (band src[2], 0xF), 4), (rshift src[3], 2)
        if #src > 3
            table.insert ret, bor (lshift (band src[3], 0x3), 6), src[4]

        pos += #src

    return table.concat [string.char i for i in *ret]

class ASSFile
    new: (file)=>
        @sections = {}
        @styles = {}
        @events = {}
        @script_info = {}
        @script_info_mapping = {}
        @aegisub_garbage = {}
        @aegisub_garbage_mapping = {}
        @extradata = {}
        @extradata_mapping = {}

        @parse file

    parse: (file)=>
        @read_sections file

        @parse_extradata!
        @script_info = @parse_section "Script Info", {"info": true}
        @aegisub_garbage = @parse_section "Aegisub Project Garbage", {"info": true}
        @styles = @parse_section "V4+ Styles", {"style": true}
        @events = @parse_section "Events", {"dialogue": true}

        for info in *@script_info
            @script_info_mapping[info.key] = info.value
        for garbage in *@aegisub_garbage
            @aegisub_garbage_mapping[garbage.key] = garbage.value

    read_sections: (file)=>
        current_section = nil

        -- read lines from file, sort into sections
        for row in file\lines!
            -- remove BOM if present, remove newlines, and trim leading spaces
            row = F.string.trimLeft (row\gsub "^\xEF\xBB\xBF", "")\gsub "[\r\n]*$", ""

            if row == "" or row\match "^;"
                continue

            section = row\match "^%[(.*)%]$"
            if section
                current_section = section
                @sections[current_section] = {}
                continue

            table.insert @sections[current_section], row

    parse_extradata: =>
        if @sections["Aegisub Extradata"]
            for row in *@sections["Aegisub Extradata"]
                line = parser.raw_to_line row
                if not line or line.class != "data"
                    aegisub.log 2, "WARNING: Malformed data line: #{row}\n"
                    continue

                @extradata[line.id] = line
                @extradata_mapping[line.key] = @extradata_mapping[line.key] or {}
                @extradata_mapping[line.key][line.value] = line.id

    parse_section: (section, expected_classes)=>
        lines = {}
        return lines if not @sections[section]

        format = nil
        for row in *@sections[section]
            line = parser.raw_to_line row, @extradata, format

            if not line
                aegisub.log 2, "WARNING: Malformed line: #{line}\n"
            elseif line.class == "format"
                format = line.format
            elseif expected_classes[line.class]
                table.insert lines, line
            else
                aegisub.log 2, "WARNING: Unexpected type #{line.class} in section #{section}\n"

        return lines

parser.parse_file = (file)->
    return ASSFile file

parser.generate_styles_section = (styles, callback)->
    callback "[V4+ Styles]\n"
    callback "Format: #{STYLE_FORMAT_STRING}\n"
    for line in *styles
        callback parser.line_to_raw(line) .. "\n"

parser.generate_events_section = (events, extradata_mapping, callback)->
    callback "[Events]\n"
    callback "Format: #{EVENT_FORMAT_STRING}\n"

    -- find the largest extradata ID seen so far
    last_eid = 0
    if extradata_mapping
        for key, v in pairs extradata_mapping
            for value, eid in pairs v
                last_eid = math.max last_eid, eid

    extradata_to_write = {}

    for line in *events
        -- handle extradata
        if line.extra and extradata_mapping
            lineindices = {}
            for key, value in pairs line.extra
                -- look for data in the original file's extradata
                cached_id = extradata_mapping[key] and extradata_mapping[key][value]
                if not cached_id
                    -- if new extradata, generate new ID and cache it
                    last_eid += 1
                    cached_id = last_eid
                    extradata_mapping[key] = extradata_mapping[key] or {}
                    extradata_mapping[key][value] = cached_id

                table.insert lineindices, cached_id
                extradata_to_write[cached_id] = {key, value}

            -- add indices to line text (e.g. {=32=33}Text)
            if #lineindices > 0
                table.sort lineindices
                indexstring = table.concat ["=#{ind}" for ind in *lineindices]
                line.text = "{#{indexstring}}" .. line.text

        callback parser.line_to_raw(line) .. "\n"

    out_indices = [ind for ind, _ in pairs extradata_to_write]
    if #out_indices > 0
        callback "\n[Aegisub Extradata]\n"

        table.sort out_indices
        for ind in *out_indices
            {key, value} = extradata_to_write[ind]
            encoded_data = parser.inline_string_encode value
            -- a mystical incantation passed down from subtitle_format_ass.cpp
            if 4*#value < 3*#encoded_data
                value = "u" .. parser.uuencode value
            else
                value = "e" .. encoded_data
            callback "Data: #{ind},#{key},#{value}\n"

parser.generate_script_info_section = (lines, callback, bom=true)->
    if bom
        callback "\xEF\xBB\xBF"
    callback "[Script Info]\n"
    for line in *lines
        callback parser.line_to_raw(line) .. "\n"

parser.generate_aegisub_garbage_section = (lines, callback)->
    callback "[Aegisub Project Garbage]\n"
    for line in *lines
        callback parser.line_to_raw(line) .. "\n"

parser.generate_file = (script_info, aegisub_garbage, styles, events, extradata_mapping, callback)->
    sec_added = false
    new_section = ->
        if sec_added
            callback "\n"
        sec_added = true

    if script_info
        new_section!
        parser.generate_script_info_section script_info, callback
    if aegisub_garbage
        new_section!
        parser.generate_aegisub_garbage_section aegisub_garbage, callback
    if styles
        new_section!
        parser.generate_styles_section styles, callback
    if events
        new_section!
        parser.generate_events_section events, extradata_mapping, callback

parser.version = version
return version\register parser

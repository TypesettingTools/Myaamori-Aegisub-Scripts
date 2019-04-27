
export script_name = "Merge Scripts"
export script_description = "Experimental automation for QC merging/exporting"
export script_version = "0.0.2"
export script_author = "Myaamori"
export script_namespace = "myaa.MergeScripts"

DependencyControl = require 'l0.DependencyControl'
depctrl = DependencyControl {
    {
        "aegisub.util", "aegisub.re", "json",
        {"myaa.pl", version: "1.6.0", url: "https://github.com/Myaamori/Penlight",
         feed: "https://raw.githubusercontent.com/Myaamori/Myaamori-Aegisub-Scripts/master/DependencyControl.json"}
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
    }
}

util, re, json, pl, F = depctrl\requireModules!
{:path, :stringx} = pl
stringx.import!

import lshift, rshift, band, bor from bit


STYLE_FORMAT_STRING = "Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, " ..
        "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, " ..
        "Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, " ..
        "MarginV, Encoding"
EVENT_FORMAT_STRING = "Layer, Start, End, Style, Name, MarginL, MarginR, " ..
        "MarginV, Effect, Text"

find = (tbl, predicate)->
    for i, v in ipairs tbl
        return v, i if predicate v, i, tbl

split = (str, sep = " ", num_splits = -1) ->
    init = 1
    first, last = str\find sep, 1, true
    -- fast return if there's nothing to split - saves one str.sub()
    return {str} if not first

    splits, s = {}, 1
    while first and s != num_splits
        splits[s] = str\sub init, first - 1
        s += 1
        init = last + 1
        first, last = str\find sep, init, plain

    splits[s] = str\sub init
    return splits, s

assTimecode2ms = (tc) ->
    local split
    split, num = {tc\match "^(%d):(%d%d):(%d%d)%.(%d%d)$"}, tonumber
    if #split != 4
        return nil, "invalid ASS timecode"
    return ((num(split[1])*60 + num(split[2]))*60 + num(split[3]))*1000 + num(split[4])*10

line_to_raw = (line)->
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

-- pointless class with static methods (basically just a namespace)
class LineFactory
    @dialogue_defaults:
        actor: "", class: "dialogue", comment: false, effect: "",
        start_time: 0, end_time: 0, layer: 0, margin_l: 0,
        margin_r: 0, margin_t: 0, section: "[Events]", style: "Default",
        text: "", extra: nil

    @style_defaults:
        class: "style", section: "[V4+ Styles]", name: "Default",
        fontname: "Arial", fontsize: 45, color1: "&H00FFFFFF",
        color2: "&H000000FF", color3: "&H00000000", color4: "&H00000000",
        bold: false, italic: false, underline: false, strikeout: false,
        scale_x: 100, scale_y: 100, spacing: 0, angle: 0,
        borderstyle: 1, outline: 4.5, shadow: 4.5, align: 2,
        margin_l: 23, margin_r: 23, margin_t: 23, encoding: 1

    create_line_from: (line, fields)=>
        line = util.copy line
        if fields
            for key, value in pairs fields
                line[key] = value
        return line

    create_dialogue_line: (fields)=> @create_line_from @@dialogue_defaults, fields

    create_style_line: (fields)=> @create_line_from @@style_defaults, fields

    from_raw: (type, raw, format, extradata)=>
        elements = split raw, ",", #format
        return nil if #elements != #format

        fields = {format[i], elements[i] for i=1,#elements}

        if type == "Dialogue" or type == "Comment"
            line = @create_dialogue_line
                actor: fields.Name, comment: type == "Comment"
                effect: fields.Effect, start_time: assTimecode2ms(fields.Start)
                end_time: assTimecode2ms(fields.End), layer: tonumber(fields.Layer)
                margin_l: tonumber(fields.MarginL), margin_r: tonumber(fields.MarginR)
                margin_t: tonumber(fields.MarginV), style: fields.Style
                text: fields.Text

            -- handle extradata (e.g. '{=32=33}Line text')
            extramatch = re.match line.text, "^\\{((?:=\\d+)+)\\}(.*)$"
            if extramatch
                line.text = extramatch[3].str
                for key in extramatch[2].str\gmatch "=(%d+)"
                    if extradata[key]
                        {field, value} = extradata[key]
                        line.extra[field] = value

            return line
        elseif type == "Style"
            boolean_map = {"-1": true, "0": false}
            line = @create_style_line
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

inline_string_decode = (input)->
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

uudecode = (input)->
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

get_format = (format_string)-> [match for match in format_string\gmatch "([^, ]+)"]

get_data = (line)->
    line.extra and line.extra[script_namespace] and json.decode line.extra[script_namespace]

parse_file = (filename, line_factory)->
    current_section = nil

    file = io.open filename
    if not file
        return nil, "Could not open file"

    sections = {}

    -- read lines from file, sort into sections
    for row in file\lines!
        -- remove BOM if present and trim
        row = F.string.trim row\gsub "^\xEF\xBB\xBF", ""

        if row == "" or row\match "^;"
            continue

        section = row\match "^%[(.*)%]$"
        if section
            current_section = section
            sections[current_section] = {}
            continue

        key, value = row\match "^([^:]+):%s*(.*)$"
        if key and value
            table.insert sections[current_section], {key, value}
            continue

        aegisub.log "WARNING: Unexpected line: #{row}\n"
        hex = table.concat [string.format "0x%x", string.byte(x) for x in row\gmatch "."], ","
        aegisub.log "Hex: #{hex}\n"

    -- parse extradata
    extradata = {}
    if sections["Aegisub Extradata"]
        for {key, value} in *sections["Aegisub Extradata"]
            if key != "Data"
                aegisub.log "WARNING: Unrecognized extradata key: #{key}\n"
                continue

            num, dkey, enc, data = value\match "^(%d+),([^,]*),([eu])(.*)$"
            if not num
                aegisub.log "WARNING: Malformed extradata line: #{value}\n"
                continue

            if enc == 'e'
                data = inline_string_decode data
            else
                data = uudecode data

            extradata[num] = {dkey, data}

    -- retrieve script info
    script_info = {}
    if sections["Script Info"]
        script_info = {key, value for {key, value} in *sections["Script Info"]}

    -- retrieve aegisub project garbage
    aegisub_garbage = sections["Aegisub Project Garbage"] or {}


    parse_section = (section, format, expected_events)->
        lines = {}
        return lines if not sections[section]

        for {type, line} in *sections[section]
            if type == "Format"
                format = get_format line
            elseif expected_events[type]
                parsed_line = line_factory\from_raw type, line, format, extradata
                if parsed_line
                    table.insert lines, parsed_line
                else
                    aegisub.log "WARNING: Malformed line of type #{type}: #{line}\n"
            else
                aegisub.log "WARNING: Unexpected type #{type} in section #{section}\n"

        return lines

    -- parse styles
    style_format = get_format STYLE_FORMAT_STRING
    styles = parse_section "V4+ Styles", style_format, {"Style": true}

    -- parse events
    event_format = get_format EVENT_FORMAT_STRING
    events = parse_section "Events", event_format, {"Dialogue": true, "Comment": true}

    return script_info, styles, events, extradata, aegisub_garbage

merge = (subtitles, selected_lines)->
    selected_lines = selected_lines or [i for i, sub in ipairs subtitles]

    script_path = aegisub.decode_path("?script")
    factory = LineFactory!

    -- keep track of indices already used for namespaces to avoid duplicates
    used_indices = {}
    for line in *subtitles
        data = get_data line
        if data
            used_indices[data.index] = true

    lines = {}
    index = 0
    for i in *selected_lines
        line = subtitles[i]
        -- find import definitions among selected lines
        if (line.effect != "import" and line.effect != "import-shifted") or
                (line.extra and line.extra[script_namespace])
            continue
        index += 1
        while used_indices[index]
            index += 1

        -- parse file to import
        file_path = path.join script_path, line.text
        script_info, styles, events, extradata, aegisub_garbage = parse_file file_path, factory
        if not script_info
            aegisub.log "ERROR: #{styles}\n"
            return

        -- bookkeeping (needed for export etc)
        extra_data = {index: index, file: file_path}

        if line.effect == "import-shifted"
            -- find sync line in external file and shift lines to match the import line
            sync_line = F.list.find events, (x)-> x.effect == "sync"
            if not sync_line
                aegisub.log "ERROR: Couldn't find sync line in #{file_path}\n"
                return

            extra_data.sync_line = sync_line.start_time

            start_diff = sync_line.start_time - line.start_time
            for event_line in *events
                event_line.start_time -= start_diff
                event_line.end_time -= start_diff

        -- add extra data
        line.extra[script_namespace] = json.encode extra_data
        subtitles[i] = line

        table.insert lines, {index, i, styles, events}

    _, first_dialogue = F.list.find subtitles, (x)-> x.class == "dialogue"

    -- keep track of how many lines have been added to ensure they're
    -- inserted in the right place
    offset = 0
    style_offset = 0
    -- insert external lines
    for {i, ref_pos, styles, events} in *lines
        for style in *styles
            style.name = "#{i}$" .. style.name
            -- insert style before the first dialogue line
            subtitles.insert first_dialogue + style_offset, style
            offset += 1
            style_offset += 1

        for event in *events
            event.style = "#{i}$" .. event.style
            -- insert line below the import definition
            subtitles.insert ref_pos + offset + 1, event
            offset += 1

clear_merged = (subtitles, selected_lines)->
    indices_to_clear = {}
    selected_lines = selected_lines or [i for i, line in ipairs subtitles]

    -- determine what files to remove based on selection
    for i in *selected_lines
        line = subtitles[i]
        if line.class != "dialogue"
            continue

        data = get_data line
        if data
            indices_to_clear[data.index] = true
            continue

        {ind, style} = line.style\split "$", 2
        if style and tonumber(ind) != nil
            indices_to_clear[tonumber ind] = true

    -- delete lines corresponding to the namespaces to remove
    lines_to_delete = {}
    for i, line in ipairs subtitles
        if line.class == "style"
            {ind, style} = line.name\split "$", 2
            ind = tonumber ind
            if style and ind != nil and indices_to_clear[ind]
                table.insert lines_to_delete, i
        elseif line.class == "dialogue"
            -- clear extradata on import lines but don't remove them
            data = get_data line
            if data and indices_to_clear[data.index]
                line.extra[script_namespace] = nil
                subtitles[i] = line
                continue

            {ind, style} = line.style\split "$", 2
            ind = tonumber ind
            if style and ind != nil and indices_to_clear[ind]
                table.insert lines_to_delete, i

    subtitles.delete lines_to_delete

prompt = (text)->
    aegisub.dialog.display({{class: "textbox", text: text, height: 20, width: 40}})

generate_release = (subtitles, selected_lines, active_line)->
    -- collect style and dialogue lines
    styles = [line for line in *subtitles when line.class == "style"]
    dialogue_lines = {}
    files = {}
    for i, line in ipairs subtitles
        -- don't include comments or empty lines
        if line.class == "dialogue" and not line.comment and #line.text > 0
            table.insert dialogue_lines, {i, line}

        -- find the source files for each namespace for error reporting
        data = get_data line
        if data
            files[data.index] = line.text

    -- find what styles are actually used by dialogue lines
    used_styles = {line.style, true for {i, line} in *dialogue_lines}

    -- remove namespace from styles and detect clashing styles
    lines = {}
    added_styles = {}
    clashing_styles = false
    for style in *styles
        {file, sname} = style.name\split "$", 2
        if used_styles[style.name]
            if sname
                index = tonumber file
                style.source_file = files[index]
                style.name = sname
            else
                style.source_file = "[current file]"

            added_styles[style.name] = added_styles[style.name] or {}
            table.insert added_styles[style.name], style
            if #added_styles[style.name] >= 2 and
                    line_to_raw(added_styles[style.name][1]) != line_to_raw(style)
                clashing_styles = true
                continue

            table.insert lines, style

    -- remove namespace from dialogue lines
    for {i, dialogue} in *dialogue_lines
        {file, sname} = dialogue.style\split "$", 2
        if sname
            dialogue.style = sname

        table.insert lines, dialogue

    if clashing_styles
        text = "Found clashing styles:\n\n"

        for style_name, styles in pairs added_styles
            if #styles < 2
                continue

            first_style = line_to_raw styles[1]
            text ..= "Styles with the name '#{style_name}' appear in multiple files " ..
                "with different definitions:\n"
            for i, style in ipairs styles
                text ..= "- " .. style.source_file
                text ..= " (clashes; ignored)" if line_to_raw(style) != first_style
                text ..= "\n"
            text ..= "\n"


        text ..= "Continue?"

        if not prompt text
            return

    all_lines = for i, line in ipairs subtitles
        if line.class == "dialogue" or line.class == "style" then i else continue
    subtitles.delete all_lines

    for line in *lines
        subtitles[0] = line

export_changes = (subtitles, selected_lines, active_line)->
    lines = {}

    -- find lines to export
    for line in *subtitles
        if line.class == "style" or line.class == "dialogue"
            local file, style
            if line.class == "style"
                {file, style} = line.name\split "$", 2
                line.name = style
            elseif line.class == "dialogue"
                {file, style} = line.style\split "$", 2
                line.style = style

            -- current line should not be exported
            if not style
                continue

            file = tonumber file
            lines[file] = lines[file] or {style: {}, dialogue: {}}
            table.insert lines[file][line.class], line

    script_path = aegisub.decode_path "?script"
    outputs = {}

    -- find import definition lines and construct the corresponding output files
    for sub in *subtitles
        data = get_data sub
        if not data
            continue

        i = data.index

        file = io.open data.file
        if not file
            aegisub.log "ERROR: Could not find #{data.file}\n"
            continue

        out_text = {}

        -- keep all lines before the styles section as is
        for row in file\lines!
            row = F.string.trim row
            if row == "[V4+ Styles]"
                break

            table.insert out_text, "#{row}\n"
        file\close!

        flines = lines[i]

        table.insert out_text, "[V4+ Styles]\n"
        table.insert out_text, "Format: #{STYLE_FORMAT_STRING}\n"
        if flines
            for line in *flines["style"]
                table.insert out_text, line_to_raw(line) .. "\n"
        table.insert out_text, "\n"

        table.insert out_text, "[Events]\n"
        table.insert out_text, "Format: #{EVENT_FORMAT_STRING}\n"

        -- shift back timings for import-shifted lines
        sync_diff = 0
        if data.sync_line
            sync_diff = sub.start_time - data.sync_line

        if flines
            for line in *flines["dialogue"]
                line.start_time = math.max(line.start_time - sync_diff, 0)
                line.end_time = math.max(line.end_time - sync_diff, 0)
                table.insert out_text, line_to_raw(line) .. "\n"

        outputs[data.file] = table.concat out_text

    text = "Do you really wish to overwrite the below files?\n\n"
    text ..= table.concat [fname for fname, output in pairs outputs], "\n"
    if not prompt text
        return

    -- write to files
    for fname, output in pairs outputs
        file = io.open fname, 'w'
        file\write output
        file\close!

script_is_saved = (subtitles, selected_lines, active_line)->
    aegisub.decode_path("?script") != "?script"

include_file = (subtitles, effect)->
    script_path = aegisub.decode_path("?script") .. "/"
    file_names = aegisub.dialog.open "Choose file to include", "", script_path, "*.ass", true

    factory = LineFactory!
    if file_names
        for f in *file_names
            line = factory\create_dialogue_line
                effect: effect, text: path.relpath(f, script_path), comment: true

            if effect == "import-shifted"
                vidpos = aegisub.ms_from_frame aegisub.project_properties!.video_position
                line.start_time = vidpos
                line.end_time = vidpos

            subtitles.append line

add_sync_line = (subtitles, selected_lines, active_line)->
    factory = LineFactory!
    vidpos = aegisub.ms_from_frame aegisub.project_properties!.video_position
    line = factory\create_dialogue_line
        effect: "sync", comment: true,
        start_time: vidpos, end_time: vidpos

    subtitles.insert active_line, line
    return {active_line}, active_line

depctrl\registerMacros {
    {
        "Add file to include",
        "Adds an import definition signifying an external file to be imported",
        (subtitles) -> include_file(subtitles, "import"),
        script_is_saved
    },
    {
        "Add file to include (shifted)",
        "Adds an import definition signifying an external file to be imported and shifted based on the synchronization line",
        (subtitles) -> include_file(subtitles, "import-shifted"),
        script_is_saved
    },
    {
        "Add synchronization line for shifted imports",
        "Adds a synchronization line at the current video time, for use with shifted imports",
        add_sync_line
    },
    {
        "Import all external files",
        "Import lines from external files corresponding to all import definitions in this file",
        (subtitles, selected_lines) -> merge(subtitles, nil),
        script_is_saved
    },
    {
        "Import selected external file(s)",
        "Import lines from external files corresponding to the selected import definitions",
        (subtitles, selected_lines) -> merge(subtitles, selected_lines),
        script_is_saved
    },
    {
        "Remove all external files",
        "Remove all lines in the file that were imported from external files",
        (subtitles, selected_lines) -> clear_merged(subtitles, nil)
    },
    {
        "Remove selected external file(s)",
        "Remove the lines in the file that were imported from external files corresponding to the selected lines",
        (subtitles, selected_lines) -> clear_merged(subtitles, selected_lines)
    },
    {
        "Generate release candidate",
        "Removes comments and style namespaces",
        generate_release
    },
    {
        "Export changes",
        "Export changes to imported lines to source files",
        export_changes
    }
}

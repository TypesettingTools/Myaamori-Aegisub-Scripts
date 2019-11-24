
export script_name = "Merge Scripts"
export script_description = "Experimental automation for QC merging/exporting"
export script_version = "0.0.12"
export script_author = "Myaamori"
export script_namespace = "myaa.MergeScripts"

DependencyControl = require 'l0.DependencyControl'
depctrl = DependencyControl {
    {
        "json",
        {"myaa.pl", version: "1.6.0", url: "https://github.com/Myaamori/Penlight",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Myaamori-Aegisub-Scripts/master/DependencyControl.json"}
        {"myaa.ASSParser", version: "0.0.4", url: "https://github.com/TypesettingTools/Myaamori-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Myaamori-Aegisub-Scripts/master/DependencyControl.json"}
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
    }
}

json, pl, parser, F = depctrl\requireModules!
{:path, :stringx} = pl
stringx.import!

get_data = (line)->
    line.extra and line.extra[script_namespace] and json.decode line.extra[script_namespace]

process_imports = (subtitles, selected_lines)->
    selected_lines = selected_lines or [i for i, sub in ipairs subtitles]

    script_path = aegisub.decode_path("?script")

    -- keep track of prefixes already used for namespaces to avoid duplicates
    used_prefixes = {}
    for line in *subtitles
        data = get_data line
        if data
            used_prefixes[data.prefix] = true

    imports = {}
    prefix = 0
    for i in *selected_lines
        line = subtitles[i]
        -- find import definitions among selected lines
        if (line.effect != "import" and line.effect != "import-shifted") or
                (line.extra and line.extra[script_namespace])
            continue
        prefix += 1
        while used_prefixes[prefix]
            prefix += 1

        -- parse file to import
        file_path = path.join script_path, line.text
        file = io.open file_path
        if not file
            aegisub.log 0, "FATAL: Could not find #{file_path}\n"
            return nil

        assfile = parser.parse_file file
        file\close!

        -- bookkeeping (needed for export etc)
        import_metadata = {prefix: prefix, file: file_path, extrakeys: assfile.extradata_mapping}

        -- increment layer if specified
        for event_line in *assfile.events
            event_line.layer += line.layer

        if line.effect == "import-shifted"
            -- find sync line in external file and shift lines to match the import line
            sync_line = F.list.find assfile.events, (x)-> x.effect == "sync"
            if not sync_line
                aegisub.log 0, "FATAL: Couldn't find sync line in #{file_path}\n"
                return nil

            import_metadata.sync_line = sync_line.start_time

            start_diff = sync_line.start_time - line.start_time
            for event_line in *assfile.events
                event_line.start_time -= start_diff
                event_line.end_time -= start_diff

        table.insert imports, {:prefix, import_line: i, :assfile, :import_metadata,
                               file_name: line.text}

    return imports

find_conflicting_script_info = (subtitles, imports)->
    check_fields = {"PlayResY", "PlayResX", "YCbCr Matrix", "WrapStyle"}
    seen_values = {field, {} for field in *check_fields}

    -- collate script properties from all imported files
    for imp in *imports
        for field, value in pairs imp.assfile.script_info_mapping
            if not seen_values[field]
                continue

            seen_values[field][value] = seen_values[field][value] or {}
            table.insert seen_values[field][value], imp.file_name

    current_script_info = {}
    for i, line in ipairs subtitles
        if line.class == "info"
            current_script_info[line.key] = {index: i, line: line}

    dialogue_fields = {
        {x: 0, y: 0, height: 1, width: 20, class: "label", label: "Conflicting values found:"}
    }
    conflicting_fields = {}
    -- use values from current script as default values
    confirmed_fields = {field, current_script_info[field].line.value for field in *check_fields}
    i = 1
    for field in *check_fields
        values = [key for key, _ in pairs seen_values[field]]
        if #values > 1
            table.insert conflicting_fields, field
            hint = {}
            for field_value in *values
                for filename in *seen_values[field][field_value]
                    table.insert hint, "#{filename}: #{field_value}"
            hint = table.concat hint, "\n"

            table.insert dialogue_fields, {
                class: "label", label: field, x: 0, y: i, height: 1, width: 10
            }
            table.insert dialogue_fields, {
                class: "dropdown", items: values, value: values[1],
                x: 10, y: i, height: 1, width: 10, hint: hint, name: field
            }
            i += 1
        elseif #values == 1
            confirmed_fields[field] = values[1]
        -- else: no values found in external scripts, keep current value

    if #conflicting_fields > 0
        button, result = aegisub.dialog.display dialogue_fields
        if not button
            return false
        for field in *conflicting_fields
            confirmed_fields[field] = result[field]

    for field, field_value in pairs confirmed_fields
        {:index, :line} = current_script_info[field]
        line.value = field_value
        subtitles[index] = line

    return true

add_imports = (subtitles, imports)->
    _, first_dialogue = F.list.find subtitles, (x)-> x.class == "dialogue"

    -- keep track of how many lines have been added to ensure they're
    -- inserted in the right place
    offset = 0
    style_offset = 0
    -- insert external lines
    for imp in *imports
        -- add extra data
        import_line_pos = imp.import_line + offset
        import_line = subtitles[import_line_pos]
        import_line.extra[script_namespace] = json.encode imp.import_metadata
        subtitles[import_line_pos] = import_line

        for style in *imp.assfile.styles
            style.name = "#{imp.prefix}$" .. style.name
            -- insert style before the first dialogue line
            subtitles.insert first_dialogue + style_offset, style
            offset += 1
            style_offset += 1

        for event in *imp.assfile.events
            event.style = "#{imp.prefix}$" .. event.style
            -- insert line below the imp definition
            subtitles.insert imp.import_line + offset + 1, event
            offset += 1

merge = (subtitles, selected_lines)->
    imports = process_imports subtitles, selected_lines
    if not imports
        return false

    -- don't set script info if no imports found
    if #imports == 0
        return true

    if not find_conflicting_script_info subtitles, imports
        return false

    add_imports subtitles, imports
    return true


clear_merged = (subtitles, selected_lines)->
    prefixes_to_clear = {}
    selected_lines = selected_lines or [i for i, line in ipairs subtitles]

    -- determine what files to remove based on selection
    for i in *selected_lines
        line = subtitles[i]
        if line.class != "dialogue"
            continue

        data = get_data line
        if data
            prefixes_to_clear[data.prefix] = true
            continue

        {prefix, style} = F.string.split line.style, "$", 1, true, 1
        if style and tonumber(prefix) != nil
            prefixes_to_clear[tonumber prefix] = true

    -- delete lines corresponding to the namespaces to remove
    lines_to_delete = {}
    for i, line in ipairs subtitles
        if line.class == "style"
            {prefix, style} = F.string.split line.name, "$", 1, true, 1
            prefix = tonumber prefix
            if style and prefix != nil and prefixes_to_clear[prefix]
                table.insert lines_to_delete, i
        elseif line.class == "dialogue"
            -- clear extradata on import lines but don't remove them
            data = get_data line
            if data and prefixes_to_clear[data.prefix]
                line.extra[script_namespace] = nil
                subtitles[i] = line
                continue

            {prefix, style} = F.string.split line.style, "$", 1, true, 1
            prefix = tonumber prefix
            if style and prefix != nil and prefixes_to_clear[prefix]
                table.insert lines_to_delete, i

    subtitles.delete lines_to_delete

find_import_definitions = (subtitles, predicate=->true)->
    import_lines = {}
    for i, line in ipairs subtitles
        if line.class == "dialogue" and
                (line.effect == "import" or line.effect == "import-shifted") and
                predicate line
            table.insert import_lines, i
    return import_lines

import_gui = (subtitles, selected_lines, active_line)->
    dialog = {
        {
            class: "label", x: 0, y: 0
            label: "Select files to import. Files not selected will be unimported if already imported."
        }
    }
    y = 1
    for i in *find_import_definitions subtitles
        line = subtitles[i]
        data = get_data line
        table.insert dialog, {
            class: "checkbox", x: 0, y: y
            value: data != nil, label: line.text
            name: tostring(i)
        }
        y += 1

    button, result = aegisub.dialog.display dialog
    if not button
        return

    to_import = [tonumber i for i, val in pairs result when val]
    table.sort to_import

    -- add temporary extradata to imports to remove
    -- to make it easier to find the lines again post merge
    for i, val in pairs result
        if not val
            j = tonumber i
            line = subtitles[j]
            line.extra._TMP_MERGESCRIPTS = ""
            subtitles[j] = line

    merge_success = merge subtitles, to_import

    -- remove temporary extradata regardless of whether merge succeeded
    to_remove = find_import_definitions subtitles, (line)->line.extra._TMP_MERGESCRIPTS != nil
    for i in *to_remove
        line = subtitles[i]
        line.extra._TMP_MERGESCRIPTS = nil
        subtitles[i] = line

    if not merge_success
        return

    clear_merged subtitles, to_remove


prompt = (text)->
    aegisub.dialog.display({{class: "textbox", text: text, height: 20, width: 40}})

_count_unique = (l)->
    counter = 0
    unique_vals = {}
    for i in *l
        if not unique_vals[i]
            unique_vals[i] = true
            counter += 1
    return counter

generate_release = (subtitles, selected_lines, active_line)->
    -- collect lines per class
    lines = {info: {}, style: {}, dialogue: {}}
    files = {}
    for line in *subtitles
        -- find the source files for each namespace for error reporting
        data = get_data line
        if data
            files[data.prefix] = line.text
            continue

        -- don't include comments or empty lines
        if line.class == "dialogue" and (line.comment or #line.text == 0)
            continue

        if lines[line.class]
            table.insert lines[line.class], line

    -- find what styles are actually used by dialogue lines
    used_styles = {line.style, true for line in *lines.dialogue}

    -- remove namespace from styles and detect clashing styles
    filtered_styles = {}
    added_styles = {}
    clashing_styles = false
    for style in *lines.style
        if not used_styles[style.name]
            continue

        {prefix, orig_name} = F.string.split style.name, "$", 1, true, 1
        if orig_name
            style.source_file = files[tonumber prefix]
            style.name = orig_name
        else
            style.source_file = "[current file]"

        added_styles[style.name] = added_styles[style.name] or {}
        table.insert added_styles[style.name], style
        if #added_styles[style.name] >= 2 and
                parser.line_to_raw(added_styles[style.name][1]) != parser.line_to_raw(style)
            clashing_styles = true
            continue

        table.insert filtered_styles, style

    lines.style = filtered_styles

    -- remove namespace from dialogue lines
    for event in *lines.dialogue
        {file, orig_style} = F.string.split event.style, "$", 1, true, 1
        if orig_style
            event.style = orig_style

    if clashing_styles
        text = "Found clashing styles:\n\n"

        for style_name, styles in pairs added_styles
            if _count_unique([parser.line_to_raw style for style in *styles]) < 2
                continue

            first_style = parser.line_to_raw styles[1]
            text ..= "Styles with the name '#{style_name}' appear in multiple files " ..
                "with different definitions:\n"
            for style in *styles
                text ..= "- " .. style.source_file
                text ..= " (clashes; ignored)" if parser.line_to_raw(style) != first_style
                text ..= "\n"
            text ..= "\n"


        text ..= "Continue?"

        if not prompt text
            return

    script_path = aegisub.decode_path("?script") .. "/"
    script_path = "" if script_path == "?script/"
    out_file_name = aegisub.dialog.save "Save release candidate", "", script_path, "*.ass"
    if not out_file_name
        return

    file, error = io.open(out_file_name, 'w')
    if not file
        aegisub.log 0, "FATAL: Could not open #{out_file_name} for writing: #{error}\n"
        return


    parser.generate_file lines.info, nil, lines.style, lines.dialogue, nil, (line) ->
        file\write line

    file\close!

get_imported_lines = (subtitles)->
    imports = {}
    lines = {}
    -- find lines to export
    for line in *subtitles
        if line.class == "style" or line.class == "dialogue"
            local prefix, style
            if line.class == "style"
                {prefix, style} = F.string.split line.name, "$", 1, true, 1
                line.name = style
            elseif line.class == "dialogue"
                data = get_data line
                if data
                    table.insert imports, line
                    continue

                {prefix, style} = F.string.split line.style, "$", 1, true, 1
                line.style = style

            -- current line should not be exported
            if not style
                continue

            prefix = tonumber prefix
            lines[prefix] = lines[prefix] or {style: {}, dialogue: {}}
            table.insert lines[prefix][line.class], line

    return imports, lines

export_changes = (subtitles, selected_lines, active_line)->
    imports, lines = get_imported_lines subtitles
    script_path = aegisub.decode_path "?script"
    outputs = {}

    -- find import definition lines and construct the corresponding output files
    for imp in *imports
        data = get_data imp
        if not data
            continue

        file = io.open data.file
        if not file
            aegisub.log 1, "ERROR: Could not find #{data.file}, will not export this file.\n"
            continue

        header_text = {}

        -- keep all lines before the styles section as is
        for row in file\lines!
            row = F.string.trim row
            if row == "[V4+ Styles]"
                break

            table.insert header_text, "#{row}\n"
        file\close!

        imported_lines = lines[data.prefix] or {style: {}, dialogue: {}}

        -- decrement layers back to original layer
        for line in *imported_lines.dialogue
            line.layer = math.max(line.layer - imp.layer, 0)

        -- shift back timings for import-shifted lines
        if data.sync_line
            sync_diff = imp.start_time - data.sync_line
            for line in *imported_lines.dialogue
                line.start_time = math.max(line.start_time - sync_diff, 0)
                line.end_time = math.max(line.end_time - sync_diff, 0)

        outputs[data.file] = {header: table.concat(header_text), lines: imported_lines, extra: data.extrakeys}

    text = "Do you really wish to overwrite the below files?\n\n"
    text ..= table.concat [fname for fname, output in pairs outputs], "\n"
    if not prompt text
        return

    -- write to files
    for fname, output in pairs outputs
        file = io.open fname, 'w'

        file\write output.header
        parser.generate_file nil, nil, output.lines.style,
            output.lines.dialogue, output.extra, (line) ->
                file\write line

        file\close!

script_is_saved = (subtitles, selected_lines, active_line)->
    aegisub.decode_path("?script") != "?script"

relpath = (f, script_path)->
    rpath = path.relpath f, script_path

    if not path.is_windows
        return rpath

    -- recover original capitalization by replacing the end of
    -- the case normalized path with the corresponding part from the
    -- original f
    f = path.normpath f
    local k
    k = 0
    for i=1,math.min(#f, #rpath)
        ri = #rpath - i + 1
        fi = #f - i + 1
        if rpath\sub(ri, ri) != f\sub(fi, fi)\lower!
            break
        k = i

    rpath = (rpath\sub 1, #rpath - k) .. (f\sub #f - k + 1, #f)
    return rpath\gsub '\\', '/'


include_file = (subtitles, effect)->
    script_path = aegisub.decode_path("?script") .. "/"
    file_names = aegisub.dialog.open "Choose file to include", "", script_path, "*.ass", true

    if file_names
        for f in *file_names
            line = parser.create_dialogue_line
                effect: effect, text: relpath(f, script_path), comment: true

            if effect == "import-shifted"
                vidpos = aegisub.ms_from_frame aegisub.project_properties!.video_position
                line.start_time = vidpos
                line.end_time = vidpos

            subtitles.append line

add_sync_line = (subtitles, selected_lines, active_line)->
    vidpos = aegisub.ms_from_frame aegisub.project_properties!.video_position
    line = parser.create_dialogue_line
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
        "Select files to import or unimport",
        "GUI interface for quick importing and unimporting of files",
        import_gui,
        script_is_saved
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

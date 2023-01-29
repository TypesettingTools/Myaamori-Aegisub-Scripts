
export script_name = "Paste From Pad"
export script_description = "Paste text from pad over existing lines"
export script_version = "0.0.3"
export script_author = "Myaamori"
export script_namespace = "myaa.PasteFromPad"

DependencyControl = require('l0.DependencyControl') {
    {
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
    }
}

F = DependencyControl\requireModules!

ConfigHandler = DependencyControl\getConfigHandler {
    settings: {
        separator: ":",
        comment: "#",
        include_blank: false,
        always_separate: true,
        strip_tags: false,
        break_lines: false
    }
}
settings = ConfigHandler.c.settings

starts_with = (str, start)->
    return (str\sub 1, #start) == start

paste = (subtitles, selected_lines, active_line)->
    dialog = {
        {
            class: "textbox", x: 0, y: 0, width: 30, height: 15, name: "text"
        },
        {
            class: "label", label: "Actor separator", x: 0, y: 15, width: 20, height: 1
        },
        {
            class: "edit", text: settings.separator, name: "separator",
            x: 20, y: 15, width: 10, height: 1
        },
        {
            class: "label", label: "Comment starter", x: 0, y: 16, width: 20, height: 1
        },
        {
            class: "edit", text: settings.comment, name: "comment",
            x: 20, y: 16, width: 10, height: 1
        },
        {
            class: "checkbox", label: "Include blank lines", value: settings.include_blank,
            name: "include_blank", x: 0, y: 17, width: 30, height: 1
        }
    }

    button, result = aegisub.dialog.display dialog
    if not button
        return nil

    settings.separator = result.separator
    settings.comment = result.comment
    settings.include_blank = result.include_blank
    ConfigHandler\write!

    for text in *F.string.split result.text, "\n"
        if #text == 0 and not result.include_blank
            continue

        comment = false
        actor = ""

        if #result.comment > 0 and starts_with text, result.comment
            comment = true
            text = text\sub 2

        if not comment and #result.separator > 0 and #text > 0
            if not starts_with(text, " ") and not starts_with(text, "\t")
                pos = text\find result.separator, 1, true
                if pos
                    actor = F.string.trim text\sub 1, pos - 1
                    text = text\sub pos + 1

        text = F.string.trimLeft text

        if #text == 0
            comment = true

        if active_line <= #subtitles
            line = subtitles[active_line]
            line.actor = actor
            line.text = text
            line.comment = comment
            subtitles[active_line] = line
        else
            subtitles[0] = {class: "dialogue", :actor, :text, :comment,
                            layer: 0, start_time: 0, end_time: 0, style: "Default",
                            margin_l: 0, margin_r: 0, margin_t: 0, effect: ""}

        active_line += 1

copy = (subtitles, selected_lines)->
    dialog = {
        {
            class: "label", label: "Actor separator", x: 0, y: 0, width: 20, height: 1
        },
        {
            class: "edit", text: settings.separator, name: "separator",
            x: 20, y: 0, width: 10, height: 1
        },
        {
            class: "label", label: "Comment starter", x: 0, y: 1, width: 20, height: 1
        },
        {
            class: "edit", text: settings.comment, name: "comment",
            x: 20, y: 1, width: 10, height: 1
        },
        {
            class: "checkbox", label: "Always include separator", value: settings.always_separate,
            hint: "Includes actor separator even if the actor field is empty",
            name: "always_separate", x: 0, y: 2, width: 30, height: 1
        },
        {
            class: "checkbox", label: "Strip tags", value: settings.strip_tags,
            hint: "Removes {comments} and {\\override\\tags}",
            name: "strip_tags", x: 0, y: 3, width: 15, height: 1
        },
        {
            class: "checkbox", label: "Break lines", value: settings.strip_tags,
            hint: "Replaces \\N tags with actual newlines"
            name: "break_lines", x: 15, y: 3, width: 15, height: 1
        }
    }

    button, result = aegisub.dialog.display dialog
    if not button
        return nil

    settings.separator = result.separator
    settings.comment = result.comment
    settings.always_separate = result.always_separate
    settings.strip_tags = result.strip_tags
    settings.break_lines = result.break_lines
    ConfigHandler\write!

    text = {}
    for i in *selected_lines
        line = subtitles[i]

        if result.strip_tags
            line.text = line.text\gsub "{[^}]*}",  ""
        if result.break_lines
            line.text = line.text\gsub "\\[Nn]",  "\n"

        if line.comment
            table.insert text, "#{result.comment}#{line.text}"
        elseif #line.actor > 0 or result.always_separate
            table.insert text, "#{line.actor}#{result.separator} #{line.text}"
        else
            table.insert text, line.text

    aegisub.dialog.display {
        {class: "textbox", x: 0, y: 0, width: 30, height: 15, value: table.concat text, "\n"}
    }, {"OK"}

DependencyControl\registerMacros {
    {
        "Paste over from pad",
        "Paste over lines starting at the active line",
        paste,
    },
    {
        "Copy to pad",
        "Copy selected lines with the actor included",
        copy,
    }
}

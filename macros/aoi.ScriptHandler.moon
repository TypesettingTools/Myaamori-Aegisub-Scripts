export script_name = "Script Handler"
export script_description = "Save and run simple scripts without the boilerplate"
export script_version = "0.0.1"
export script_author = "Myaamori"
export script_namespace = "aoi.ScriptHandler"

F = require 'l0.Functional'
_ASS = require 'l0.ASSFoundation'
LineCollection = require 'a-mo.LineCollection'
DependencyControl = require('l0.DependencyControl') {}
moonscript = require('moonscript')

ConfigHandler = DependencyControl\getConfigHandler {
    settings:
        lastResult: nil
        profiles: {}
}

settings = ConfigHandler.c.settings

default =
    code: nil
    select: false
    all_lines: false
    newpreset: "New preset"

result = settings.lastResult or default

show_dialog = ->
    profile_names = [k for k, v in pairs settings.profiles]

    dialog = {
        {
            class: "textbox", name: "code"
            x: 0, y: 0
            height: 20, width: 50
            value: result.code
            hint: [[The following variables are available:
lines: A LineCollection object holding the lines to operate on
Line: The Line class
ASS: The ASSFoundation module]]
        },
        {
            class: "dropdown", name: "preset"
            x: 0, y: 20
            height: 1, width: 25
            items: profile_names
            value: result.preset
        },
        {
            class: "edit", name: "newpreset"
            x: 25, y: 20
            height: 1, width: 25
            text: result.newpreset
        },
        {
            class: "checkbox", name: "select"
            x: 50, y: 0
            height: 1, width: 10
            label: "Select lines"
            value: result.select
        },
        {
            class: "checkbox", name: "all_lines"
            x: 50, y: 1
            height: 1, width: 10
            label: "Run on all lines"
            value: result.all_lines
        }
    }
    aegisub.dialog.display dialog, {"Run", "Load", "Save", "Delete", "Cancel"},
        {ok: "Run", cancel: "Cancel"}

run_script = (subtitles, selected_lines, active_lines, result)->
    if result.all_lines
        export lines = LineCollection\fromAllLines subtitles
    else
        export lines = LineCollection subtitles, selected_lines

    export Line = require 'a-mo.Line'
    export ASS = _ASS
    export subs = subtitles

    compiled, error = loadstring result.code
    if error
        aegisub.dialog.display {{class: "textbox", x: 0, y: 0,
                                 height: 10, width: 20, value: error}}
        return false

    success, error = pcall compiled
    if not success
        aegisub.dialog.display {{class: "textbox", x: 0, y: 0,
                                 height: 10, width: 20, value: error}}
        return false

    lines\replaceLines!
    lines\insertLines!
    return true


process_macro = (subtitles, selected_lines, active_lines)->
    while true
        button, result = show_dialog!
        settings.lastResult = result
        ConfigHandler\write!

        if not button
            break
        elseif button == "Run"
            if run_script subtitles, selected_lines, active_lines, result
                break
        elseif button == "Load"
            if settings.profiles[result.preset]
                result = settings.profiles[result.preset]
        elseif button == "Save"
            result.preset = result.newpreset
            settings.profiles[result.newpreset] = result
            ConfigHandler\write!
        elseif button == "Delete"
            settings.profiles[result.preset] = nil
            ConfigHandler\write!
            result = default

aegisub.register_macro script_name,
    script_destription,
    process_macro

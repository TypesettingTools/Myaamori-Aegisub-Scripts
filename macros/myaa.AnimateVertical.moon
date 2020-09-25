
export script_name = "Animate Vertical"
export script_description = "Animate a vertical line"
export script_version = "0.0.1"
export script_author = "Myaamori"
export script_namespace = "myaa.AnimateVertical"

DependencyControl = require 'l0.DependencyControl'
depctrl = DependencyControl {
    {
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"}
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.Line", version: "1.5.3", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"a-mo.ConfigHandler", version: "1.1.4", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
    }
}

F, LineCollection, Line, ASS, ConfigHandler = depctrl\requireModules!

findall = (s, c) ->
    indices = {}
    for i = 1, #s
        if s\sub(i, i) == c
            table.insert indices, i
    return indices

process = (sub, sel, result) ->
    lines = LineCollection sub, sel
    lines_to_delete = {}

    distance = result.characterDistance
    column_distance = result.columnDistance
    offset_size = if result.spaceEven then 0 else 1
    delay = result.delay
    anim_size = result.maximumOffset
    anim_stop = result.finalOffset
    anim_duration = result.duration
    vertical = result.layout == "Vertical"
    direction = if result.invertDirection then -1 else 1
    split_char = result.split

    lines_added = 0

    lines\runCallback ((lines, line, i) ->
        ass = ASS\parse line
        line\getPropertiesFromStyle!

        str = ass\copy!\stripTags!\getString!

        for i, wordline in ipairs ass\splitAtIndexes findall(str, split_char), 4, false
            wordass = wordline.ASS

            if i > 1
                wordass.sections[2].value = wordass.sections[2].value\sub(2)

            lwidth, lheight = 0, 0

            for j, charline in ipairs wordass\splitAtIntervals 1, 4, false
                charass = charline.ASS

                pos = charass\getPosition!
                if vertical
                    pos\add column_distance * (i - 1), distance * (j - 1) + lheight * offset_size
                else
                    pos\add distance * (j - 1) + lwidth * offset_size, column_distance * (i - 1)
                charass\replaceTags {pos}
                charass\commit!

                cwidth, cheight = charass\getTextExtents!
                lwidth += cwidth
                lheight += cheight

                start_frame = aegisub.frame_from_ms charline.start_time
                end_frame = aegisub.frame_from_ms charline.end_time
                duration = end_frame - start_frame
                charline\tokenizeTransforms!

                for frame = start_frame, end_frame - 1
                    n = frame - start_frame
                    p = n / duration * math.pi

                    cur_time = aegisub.ms_from_frame(frame) - charline.start_time
                    copy = Line charline, lines
                    copy.start_time = aegisub.ms_from_frame frame
                    copy.end_time = aegisub.ms_from_frame (frame + 1)
                    copy\interpolateTransforms cur_time

                    cur_shift = math.max(0, math.min((2 * anim_size - anim_stop) / (2 * anim_size),
                                                     (cur_time - delay * (j - 1)) / anim_duration))
                    copyass = ASS\parse copy
                    pos = copyass\getPosition!

                    shift = direction * math.sin(cur_shift * math.pi) * anim_size
                    if vertical
                        pos\add shift, 0
                    else
                        pos\add 0, shift
                    copyass\replaceTags {pos}
                    copyass\commit!

                    lines_added += 1
                    lines\addLine copy, nil, true, line.number + lines_added

        line.comment = true
    ), true

    lines\replaceLines!
    lines\insertLines!
    return lines\getSelection!


dialog = {
  main: {
    layoutLabel: {
      class: "label", label: "Text layout: ",
      x: 0, y: 0,  width: 1, height: 1
    },
    layout: {
      class: "dropdown",
      value: "Vertical", config: true, items: {"Vertical", "Horizontal"},
      x: 1, y: 0,  width: 1, height: 1, hint: "Whether to lay out the text vertically or horizontally"
    },
    invertDirection: {
      class: "checkbox", label: "Invert animation direction",
      value: false, config: true,
      x: 0, y: 1,  width: 2, height: 1, hint: "Inverts the direction of the animation"
    },
    spaceEven: {
      class: "checkbox", label: "Space out characters evenly",
      value: true, config: true,
      x: 0, y: 3,  width: 2, height: 1, hint: "Spaces out characters evenly, ignoring their width/height; if false, characters are additionally offset by their height (vertical layout) or their width (horizontal layout)"
    },
    characterDistanceLabel: {
      class: "label", label: "Character distance:",
      x: 0, y: 4,  width: 1, height: 1
    },
    characterDistance: {
      class: "intedit",
      value: 40, config: true,
      x: 1, y: 4, width: 1, height: 1, hint: "Distance between characters on the same row/column (pixels)"
    },
    columnDistanceLabel: {
      class: "label", label: "Column/row distance:",
      x: 0, y: 5,  width: 1, height: 1
    },
    columnDistance: {
      class: "intedit",
      value: 100, config: true,
      x: 1, y: 5, width: 1, height: 1, hint: "Distance between rows/columns of characters (pixels)"
    },
    maximumOffsetLabel: {
      class: "label", label: "Maximum offset:",
      x: 0, y: 6,  width: 1, height: 1
    },
    maximumOffset: {
      class: "intedit",
      value: 100, config: true, min: 0,
      x: 1, y: 6, width: 1, height: 1, hint: "The maximum offset (peak) of the animation (pixels)"
    },
    finalOffsetLabel: {
      class: "label", label: "Final offset:",
      x: 0, y: 7,  width: 1, height: 1
    },
    finalOffset: {
      class: "intedit",
      value: 30, config: true, min: 0,
      x: 1, y: 7, width: 1, height: 1, hint: "The final offset at the end of the animation (pixels)"
    },
    durationLabel: {
      class: "label", label: "Animation duration:",
      x: 0, y: 8,  width: 1, height: 1
    },
    duration: {
      class: "intedit",
      value: 200, config: true, min: 10,
      x: 1, y: 8, width: 1, height: 1, hint: "The duration of the animation per character (ms)"
    },
    delayLabel: {
      class: "label", label: "Animation delay:",
      x: 0, y: 9,  width: 1, height: 1
    },
    delay: {
      class: "intedit",
      value: 100, config: true,
      x: 1, y: 9, width: 1, height: 1, hint: "The delay between the start of the animation for different characters (ms)"
    },
    splitLabel: {
      class: "label", label: "Split character:",
      x: 0, y: 10,  width: 1, height: 1
    },
    split: {
      class: "edit",
      value: "|", config: true,
      x: 1, y: 10, width: 1, height: 1, hint: "The character to split the text into multiple rows/columns at"
    }
  }
}

show_dialog = (sub, sel) ->
    options = ConfigHandler dialog, depctrl.configFile, false, script_version, depctrl.configDig
    options\read!
    options\updateInterface "main"
    button, result = aegisub.dialog.display dialog.main
    if button
        options\updateConfiguration result, "main"
        options\write!
        return process sub, sel, result

depctrl\registerMacros {
    {"Animate", "", show_dialog}
}

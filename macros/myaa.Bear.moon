
export script_name = "Bear"
export script_description = "Stuff for Bear^4"
export script_version = "0.0.1"
export script_author = "Myaamori"
export script_namespace = "myaa.Bear"

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

    start_angle = result.startAngle
    end_angle = result.finalAngle
    start_blur = result.startBlur
    end_blur = result.finalBlur
    accel = result.gravity
    bounces = result.bounces
    bounce_size = result.bounceHeight
    anim_duration = result.charAnimDuration
    delay = result.animDelay

    lines_added = 0

    lines\runCallback ((lines, line, i) ->
        ass = ASS\parse line
        line\getPropertiesFromStyle!

        str = ass\copy!\stripTags!\getString!
        copy = ass\copy!

        end_time = line.start_time + delay * (#str - 1) + anim_duration

        for j, charline in ipairs ass\splitAtIntervals 1, 4, true
            charass = charline.ASS

            start_frame = aegisub.frame_from_ms charline.start_time
            end_frame = aegisub.frame_from_ms end_time

            pos = charass\getPosition!

            for frame = start_frame, end_frame + 1
                cur_time = aegisub.ms_from_frame(frame) - charline.start_time

                p = math.max(0, math.min(1, (cur_time - delay * (j - 1)) / anim_duration))

                if p <= 0
                    continue

                curve = p * bounces * math.pi
                init_p = math.max(0, math.min(1, p * bounces * 2))

                copy = Line charline, lines
                copy.start_time = aegisub.ms_from_frame frame
                if p >= 1
                    copy.end_time = line.end_time
                else
                    copy.end_time = aegisub.ms_from_frame (frame + 1)
                copy\interpolateTransforms cur_time

                copyass = ASS\parse copy
                angle = ASS\createTag "angle", (1 - init_p) * start_angle + init_p * end_angle
                alpha = ASS\createTag "alpha", (1 - init_p) * 255 + init_p * 0
                blur = ASS\createTag "blur", (1 - init_p) * start_blur + init_p * end_blur
                pos = copyass\getPosition!

                pos\add 0, -bounce_size * math.abs(math.sin(curve)) * math.pow((1 - p), accel)
                copyass\replaceTags {pos, angle, alpha, blur}
                copyass\commit!

                lines_added += 1
                lines\addLine copy, nil, true, line.number + lines_added

                if p >= 1
                    break

        line.comment = true
    ), true

    lines\replaceLines!
    lines\insertLines!
    return lines\getSelection!

dialog = {
  main: {
    animDelayLabel: {
      class: "label", label: "Animation start delay:",
      x: 0, y: 0,  width: 1, height: 1
    },
    animDelay: {
      class: "intedit",
      value: 20, config: true, min: 1,
      x: 1, y: 0, width: 1, height: 1, hint: "The gap in time of the start of the animation between each character (ms)"
    },
    charAnimDurationLabel: {
      class: "label", label: "Character animation duration:",
      x: 0, y: 1,  width: 1, height: 1
    },
    charAnimDuration: {
      class: "intedit",
      value: 500, config: true, min: 0,
      x: 1, y: 1, width: 1, height: 1, hint: "The duration of the animation for each character (ms)"
    },
    startAngleLabel: {
      class: "label", label: "Start angle:",
      x: 0, y: 2,  width: 1, height: 1
    },
    startAngle: {
      class: "floatedit",
      value: 15, config: true,
      x: 1, y: 2, width: 1, height: 1, hint: "The initial angle of each character (degrees)"
    },
    finalAngleLabel: {
      class: "label", label: "Final angle:",
      x: 0, y: 3,  width: 1, height: 1
    },
    finalAngle: {
      class: "floatedit",
      value: 0, config: true,
      x: 1, y: 3, width: 1, height: 1, hint: "The final angle of each character (degrees)"
    },
    startBlurLabel: {
      class: "label", label: "Start blur:",
      x: 0, y: 4,  width: 1, height: 1
    },
    startBlur: {
      class: "floatedit",
      value: 3, config: true,
      x: 1, y: 4, width: 1, height: 1, hint: "The initial blur of each character"
    },
    finalBlurLabel: {
      class: "label", label: "Final blur:",
      x: 0, y: 5,  width: 1, height: 1
    },
    finalBlur: {
      class: "floatedit",
      value: 1, config: true,
      x: 1, y: 5, width: 1, height: 1, hint: "The final blur of each character"
    },
    bouncesLabel: {
      class: "label", label: "Bounces:",
      x: 0, y: 6,  width: 1, height: 1
    },
    bounces: {
      class: "intedit",
      value: 2, config: true, min: 1,
      x: 1, y: 6, width: 1, height: 1, hint: "The number of times each character should bounce"
    },
    bounceHeightLabel: {
      class: "label", label: "Bounce height:",
      x: 0, y: 7,  width: 1, height: 1
    },
    bounceHeight: {
      class: "intedit",
      value: 30, config: true, min: 1,
      x: 1, y: 7, width: 1, height: 1, hint: "The height of the bounces"
    },
    gravityLabel: {
      class: "label", label: "Gravity:",
      x: 0, y: 8,  width: 1, height: 1
    },
    gravity: {
      class: "floatedit",
      value: 1.2, config: true, min: 0,
      x: 1, y: 8, width: 1, height: 1, hint: "How quickly the bounce height should decrease (1 = linear, 0 = no decrease)"
    },
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
    {"Make next episode title", "", show_dialog}
}

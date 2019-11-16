DependencyControl = require "l0.DependencyControl"

version = DependencyControl {
    name: "LineCollection",
    version: "0.0.1",
    description: "Abstraction for simpler handling of subtitle lines",
    author: "Myaamori",
    url: "http://github.com/TypesettingTools/Myaamori-Aegisub-Scripts",
    moduleName: "myaa.LineCollection",
    feed: "https://raw.githubusercontent.com/TypesettingTools/Myaamori-Aegisub-Scripts/master/DependencyControl.json",
    {
    }
}

class Line
    new: (@line)=>
        mt = getmetatable @
        mt.__index = (key)=>
            if @line[key] != nil
                @line[key]
            else
                rawget @, key

    __newindex: (key, value)=>
        if @line[key] != nil
            @original_index = nil
            @line[key] = value
        else
            rawset @, key, value

class LineCollection
    @version: version
    @lineClasses = {"info", "style", "dialogue"}

    new: (@sub, @sel, @active, all_lines=false)=>
        @head = nil
        @tail = nil
        @length = 0
        @selections = {}
        @sourceLines = {cls, [] for cls in *@lineClasses}

        @collectLines all_lines
        for cls in *@lineClasses
            @addLines cls

    collectLines: (all_lines)=>
        selected = {i, true for i in *@sel}
        for i, line in ipairs @subs
            if line.class == "dialogue" and not all_lines and not selected[i]
                continue

            if sourceLines[line.class]
                line = Line line
                line.original_index = i
                table.insert sourceLines[line.class], line

    addLines: (indices)=>
        selection = 0
        for i, line_num in ipairs indices
            if i == 1 or indices[i-1] < line_num - 1
                selection += 1
                selections[selection] = {start: line_num}
            selections[selection].end = line_num

            line = Line @sub[line_num]
            if @tail
                @addAfter line, @tail
            else
                @head = line
                @tail = line
            line.selection = selection
            line.original_index = line_num

    addStyles: =>


    assertInList: (line)=>
        assert line.__class == Line, "line must be a Line object"
        assert line.parentCollection == @, "line must belong to this collection"

    assertNotInList: (line)=>
        assert line.__class == Line, "line must be a Line object"
        assert line.parentCollection == nil, "line cannot belong to a collection"

    addAfter: (line, prev)=>
        @assertNotInList line
        @assertInList prev
        line.next = prev.next
        line.prev = prev
        prev.next = line
        line.selection = prev.selection
        line.parentCollection = @

        if not line.next
            @tail = line
        @length += 1

    addBefore: (line, next)=>
        @assertNotInList line
        @assertInList next
        line.prev = next.prev
        line.next = next
        next.prev = line
        line.selection = next.selection
        line.parentCollection = @

        if not line.prev
            @head = line
        @length += 1

    deleteLine: (line)=>
        @assertInList line
        if line.prev
            line.prev.next = line.next
        else
            @head = line.next

        if line.next
            line.next.prev = line.prev
        else
            @tail = line.prev

        line.next = nil
        line.prev = nil
        line.selection = nil
        line.parentCollection = nil
        line.original_index = nil
        @length -= 1

    commit: =>
        nil


return version\register LineCollection

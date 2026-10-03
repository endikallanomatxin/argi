Widget : Type = (.value: Int32)

Widget init(.fail: Bool) -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) := {
    constructed :: Widget

    if fail {
        result = ..error(.reason = ..rejected)
        return
    }
    constructed = (.value = 42)
    result = ..ok ~constructed
}

main() -> (.status_code: Int32) := {
    widget :: Widget
    outcome ::= Widget(.fail = false)
    match outcome {
        ..ok ~value { widget = ~value status_code = widget.value - 42 }
        ..error _ { status_code = 1 }
    }
}

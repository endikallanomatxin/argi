Widget : Type = (.value: Int32)

Widget init() -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) := {
    constructed :: Widget

    result = ..error(.reason = ..rejected)
}

main() -> (.status_code: Int32) := {
    widget :: Widget
    outcome ::= Widget()
    match outcome {
        ..ok _ { status_code = 0 }
        ..error _ { status_code = widget.value }
    }
}

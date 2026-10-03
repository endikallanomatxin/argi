Widget : Type = (.value: Int32)

Widget init() -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) := {
    constructed :: Widget

    result = ..ok ~constructed
}

main() -> (.status_code: Int32) := {
    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 1 }
    }
}

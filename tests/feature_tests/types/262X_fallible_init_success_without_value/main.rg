Widget : Type = (.value: Int32)

implement Init#(Widget, ()) (
    .Result: Type = Errable#(.t: Widget, .reasons: (..rejected))
    .init = (.args: ()) -> (.result: Result) {
        constructed :: Widget

        result = ..ok ~constructed
    }
)

main() -> (.status_code: Int32) := {
    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 1 }
    }
}

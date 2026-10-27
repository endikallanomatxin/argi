Widget := (.value: Int32)

WidgetInitArgs: Type = (.fail: Bool)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {
        _init_fail ::= ~fail

        constructed :: Widget

        if _init_fail {
            result = ..error(.reason = ..rejected)
            return
        }
        constructed = (.value = 42)
        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32) {
    failed ::= Widget(.fail = true)
    match failed {
        ..error _ {}
        ..ok _ {
            status_code = 2
            return
        }
    }
    constructed ::= Widget(.fail = false)
    match constructed {
        ..ok value { status_code = value.value - 42 }
        ..error _ { status_code = 1 }
    }
}

Widget := (.value: Int32)

Wrapper := (.widget: Widget)

implement Init#(Widget) (
    .init = (.fail: Bool) -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) {
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

implement Init#(Wrapper) (
    .init = (.fail: Bool) -> (.result: Errable#(.t: Wrapper, .reasons: (..rejected))) {
        _init_fail ::= ~fail

        constructed :: Wrapper

        constructed = (.widget = Widget(.fail = _init_fail)!)
        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32 = 0) {
    failed ::= Wrapper(.fail = true)
    match failed {
        ..error _ {}
        ..ok _ {
            status_code = 1
            return
        }
    }
    built ::= Wrapper(.fail = false)
    match built {
        ..error _ { status_code = 2 }
        ..ok value { status_code = value.widget.value - 42 }
    }
}

Widget := (.value: Int32)

Wrapper := (.widget: Widget)

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

WrapperInitArgs2: Type = (.fail: Bool)

implement Init#(Wrapper, WrapperInitArgs2) (
    .Result : Type = Errable#(.t: Wrapper, .reasons: (..rejected))

    .init = WrapperInitArgs2 -> (.result: Result) {
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

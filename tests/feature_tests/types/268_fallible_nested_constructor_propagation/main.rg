Widget := (.value: Int32)
Wrapper := (.widget: Widget)

implement Init#(Widget, (.fail: Bool)) (
    .Result: Type = Errable#(.t: Widget, .reasons: (..rejected))
    .init = (.args: (.fail: Bool)) -> (.result: Result) {
        fail ::= ~args.fail

        constructed :: Widget

        if fail {
            result = ..error(.reason = ..rejected)
            return
        }
        constructed = (.value = 42)
        result = ..ok ~constructed
    }
)

implement Init#(Wrapper, (.fail: Bool)) (
    .Result: Type = Errable#(.t: Wrapper, .reasons: (..rejected))
    .init = (.args: (.fail: Bool)) -> (.result: Result) {
        fail ::= ~args.fail

        constructed :: Wrapper

        constructed = (.widget = Widget(.fail = fail)!)
        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32 = 0)  {
    failed ::= Wrapper(.fail = true)
    match failed {
        ..error _ { }
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

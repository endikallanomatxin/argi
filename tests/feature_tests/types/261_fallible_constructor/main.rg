Widget := (.value: Int32)

implement Init<Widget, (.fail: Bool)> (
    .Result: Type = Errable<.t: Widget, .reasons: (..rejected)>
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

main := () -> (.status_code: Int32)  {
    failed ::= Widget(.fail = true)
    match failed {
        ..error _ { }
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

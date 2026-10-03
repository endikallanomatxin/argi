Widget : Type = (.value: Int32)
Wrapper : Type = (.widget: Widget)

Widget init(.fail: Bool) -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) := {
    constructed :: Widget

    if fail {
        result = ..error(.reason = ..rejected)
        return
    }
    constructed = (.value = 42)
    result = ..ok ~constructed
}

Wrapper init(.fail: Bool) -> (.result: Errable#(.t: Wrapper, .reasons: (..rejected))) := {
    constructed :: Wrapper

    constructed = (.widget = Widget(.fail = fail)!)
    result = ..ok ~constructed
}

main() -> (.status_code: Int32 = 0) := {
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

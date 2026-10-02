Widget : Type = (.value: Int32)
Wrapper : Type = (.widget: Widget)

init(.p: $&Widget, .fail: Bool) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    if fail {
        result = ..error(.reason = ..rejected)
        return
    }
    p& = (.value = 42)
    result = ..ok Void()
}

init(.p: $&Wrapper, .fail: Bool) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    p& = (.widget = Widget(.fail = fail)!)
    result = ..ok Void()
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

Widget : Type = (.value: Int32)

init(.p: $&Widget, .fail: Bool) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    if fail {
        result = ..error(.reason = ..rejected)
        return
    }
    p& = (.value = 42)
    result = ..ok Void()
}

main() -> (.status_code: Int32) := {
    widget :: Widget
    outcome ::= init(.p = $&widget, .fail = false)
    match outcome {
        ..ok _ { status_code = widget.value - 42 }
        ..error _ { status_code = 1 }
    }
}

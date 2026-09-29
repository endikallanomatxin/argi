Widget : Type = (.value: Int32)

init(.p: $&Widget) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    result = ..error(.reason = ..rejected)
}

main() -> (.status_code: Int32) := {
    widget :: Widget
    outcome ::= init(.p = $&widget)
    match outcome {
        ..ok _ { status_code = 0 }
        ..error _ { status_code = widget.value }
    }
}

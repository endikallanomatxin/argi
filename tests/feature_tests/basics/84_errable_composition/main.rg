other() -> (.result: Errable#(.t: Void, .reasons: (..empty))) := {
    result = ..error(.reason = ..empty)
}

bounded() -> (.result: Errable#(.t: Void, .reasons: (..composition_failure)) = ..ok Void()) := {
    other()
}

..composition_failure

Box: Type = (.number: Int32)

boxed#(.t: Type)(.value: t) -> (.result: Errable#(.t: t, .reasons: (..composition_failure))) := {
    result = ..ok ~value
}

pass#(.t: Type)(.value: t) -> (.result: Errable#(.t: t, .reasons: (..composition_failure))) := {
    payload ::= ~boxed(.value = ~value)!
    result = ..ok ~payload
}

main() -> (.result: Errable#(.t: Void, .reasons: (..composition_failure)) = ..ok Void()) := {
    bounded()!
    value ::= pass(.value = Box(.number = 42))!
    if value.number != 42 { abort }
    match boxed(.value = 7) {
        ..ok number { if number != 7 { abort } } ..error&failure {
            if [
                failure&.reason
                != ..composition_failure
            ] { abort }
        }
    }
}

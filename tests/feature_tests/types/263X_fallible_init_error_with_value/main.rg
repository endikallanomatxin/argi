Widget : Type = (.value: Int32)

init(.p: $&Widget) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    p& = (.value = 42)
    result = ..error(.reason = ..rejected)
}

main() -> (.status_code: Int32) := {
    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 0 }
    }
}

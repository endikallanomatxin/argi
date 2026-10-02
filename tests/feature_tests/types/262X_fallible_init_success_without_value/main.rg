Widget : Type = (.value: Int32)

init(.p: $&Widget) -> (.result: Errable#(.t: Void, .reasons: (..rejected))) := {
    result = ..ok Void()
}

main() -> (.status_code: Int32) := {
    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 1 }
    }
}

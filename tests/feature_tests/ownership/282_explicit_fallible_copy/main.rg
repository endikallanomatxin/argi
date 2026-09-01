FallibleValue : Type = (
    .value: Int32
)

copy(.self: &FallibleValue) -> (.result: Errable#(.t: FallibleValue, .reasons: (..copy_failed))) := {
    result = ..ok (.value = self&.value)
}

FallibleValue implements FalliblyCopyable#(.reasons: (..copy_failed))

main() -> (.status_code: Int32) := {
    first :: FallibleValue = (.value = 21)
    copied ::= copy(.self = &first)
    match copied {
        ..error _ { status_code = 1 }
        ..ok ~ payload { status_code = first.value + payload.value - 42 }
    }
}

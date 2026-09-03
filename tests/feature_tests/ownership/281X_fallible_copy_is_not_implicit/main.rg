FallibleValue : Type = (
    .value: Int32
)

copy(.self: &FallibleValue) -> (.result: Errable#(.t: FallibleValue, .reasons: (..copy_failed))) := {
    result = ..ok (.value = self&.value)
}

FallibleValue implements FalliblyCopyable#(.reasons: (..copy_failed))

main() -> (.status_code: Int32) := {
    first :: FallibleValue = (.value = 42)
    second ::= first
    status_code = second.value - 42
}

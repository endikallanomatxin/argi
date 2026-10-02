LargeValue : Type = (
    .value: Int32
)

LargeValue implements InfalliblyCopyable

copy(.self: &LargeValue) -> (.value: LargeValue) := {
    value = (.value = self&.value)
}

main() -> (.status_code: Int32) := {
    first :: LargeValue = (.value = 42)
    second ::= first
    status_code = second.value - 42
}

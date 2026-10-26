LargeValue := (
    .value : Int32
)

implement InfalliblyCopyable<LargeValue> (
    .copy = (.self: &LargeValue) -> (.value: LargeValue) {
        value = (.value = self&.value)
    }
)

main := () -> (.status_code: Int32) {
    first :: LargeValue = (.value = 21)
    second ::= copy(.self = &first)
    status_code = first.value + second.value - 42
}

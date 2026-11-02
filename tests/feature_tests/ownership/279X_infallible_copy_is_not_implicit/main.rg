LargeValue := (
    .value : Int32
)

implement InfalliblyCopyable#(LargeValue) (
    .copy = (.self: &LargeValue) -> (.value: LargeValue) {
        value = (.value = self&.value)
    }
)

main := () -> (.status_code: Int32) {
    first :: LargeValue = (.value = 42)
    second ::= first
    status_code = second.value - 42
}

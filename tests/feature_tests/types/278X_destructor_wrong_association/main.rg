First : Type = (.value: Int32)
Second : Type = (.value: Int32)
First deinit(.self: $&Second) -> () := {}
main() -> (.status_code: Int32) := {
    second ::= Second(.value = 1)
    deinit(.self = $&second)
    status_code = 0
}

main() -> (.status_code: Int32) := {
    values :: [2]Int32
    second ::= trusted_mutable_reference_offset(.base = $&values[0], .elements = 1).reference
    second&= 42
    status_code = second&
}

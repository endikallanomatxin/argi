SelfRef : Type = (
    .value: Int32
    .reference: &Int32
)

main() -> (.status_code: Int32) := {
    seed :: Int32 = 0
    source :: SelfRef = (.value = 7, .reference = &seed)
    source.reference = &source.value

    moved ::= ~source
    status_code = moved.reference& - 7
}

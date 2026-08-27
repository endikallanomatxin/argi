SelfRef : Type = (
    .value: Int32
    .reference: &Int32
)

main() -> (.status_code: Int32) := {
    seed :: Int32 = 0
    source :: SelfRef = (.value = 7, .reference = &seed)
    source.reference = &source.value

    -- This ordinary ownership transfer is legal. It preserves the reference's
    -- dependency on source storage, so it must not be treated as permission to
    -- relocate the representation to unrelated physical storage.
    moved ::= ~source
    status_code = moved.reference& - 7
}

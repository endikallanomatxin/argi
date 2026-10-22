Resource: Type = (.value: Int32)

ReferenceRecord: Type = (.value: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

choose(.left: ReferenceRecord, .right: ReferenceRecord, .use_right: Bool) -> (
    .result : ReferenceRecord
) := {
    result = left
    while use_right {
        result = right
        return
    }
}

main() -> () := {
    first :: Resource = Resource(41)
    second :: Resource = Resource(42)
    reference ::= choose(
        .left = (.value = &first), .right = (.value = &second), .use_right = false
    )
    deinit(.self = $&first)
    observed ::= reference.value&.value
}

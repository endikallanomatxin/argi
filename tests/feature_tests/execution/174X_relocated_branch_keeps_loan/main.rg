Resource := (.value: Int32)

ReferenceRecord := (.value: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

choose := (.left: ReferenceRecord, .right: ReferenceRecord, .use_left: Bool) -> (
    .result : ReferenceRecord
) {
    if use_left {
        relocate(.source = $&left, .destination = $&result)
    } else {
        relocate(.source = $&right, .destination = $&result)
    }
}

main := () -> () {
    first :: Resource = Resource(41)
    second :: Resource = Resource(42)
    reference ::= choose(
        .left = (.value = &first), .right = (.value = &second), .use_left = true
    )
    deinit(.self = $&first)
    observed ::= reference.value&.value
}

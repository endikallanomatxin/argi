Resource: Type = (.value: Int32)

ReferenceRecord: Type = (.value: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

forward(.source: ReferenceRecord) -> (.result: ReferenceRecord) := {
    relocate(.source = $&source, .destination = $&result)
}

main() -> () := {
    owner :: Resource = Resource(42)
    reference ::= forward(.source = (.value = &owner))
    deinit(.self = $&owner)
    observed ::= reference.value&.value
}

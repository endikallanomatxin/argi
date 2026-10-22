Resource: Type = (.value: Int32)

ReferenceRecord: Type = (.value: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

Selection: Type = (..left, ..right)

choose(.left: ReferenceRecord, .right: ReferenceRecord, .selection: Selection) -> (
    .result : ReferenceRecord
) := {
    match selection {
        ..left { result = left }
        ..right { result = right }
    }
}

main() -> () := {
    first :: Resource = Resource(41)
    second :: Resource = Resource(42)
    selection: Selection = ..left
    reference ::= choose(
        .left = (.value = &first), .right = (.value = &second), .selection = selection
    )
    deinit(.self = $&first)
    observed ::= reference.value&.value
}

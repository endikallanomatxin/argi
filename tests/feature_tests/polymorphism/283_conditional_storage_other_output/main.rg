Extractor#(.Participant: Type): Contract = (
    .take: (.self: &Participant, .storage: &Allocation) -> (.tag: ?Int32, .value: Int32) where {
        on tag ..some { from_storage(value, storage) }
    }
)

main() -> () := {}

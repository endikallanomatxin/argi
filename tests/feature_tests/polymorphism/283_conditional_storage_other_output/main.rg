Extractor: Abstract = (
    take(.self: &Self, .storage: &Allocation) -> (.tag: ?Int32, .value: Int32) where {
        on tag ..some { from_storage(value, storage) }
    }
)

main() -> () := {}

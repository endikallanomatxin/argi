Extractor<.Participant: Type>: Contract = (
    .take : (.self: &Participant, .storage: &Allocation, .input: ?Int32) -> (.result: ?Int32) where {
        transfers(result, input)
        on result ..some { from_storage(result, storage) }
    }
)

Implementation: Type = ()

implement Extractor<Implementation> (.take = _take)

_take := (.self: &Implementation, .storage: &Allocation, .input: ?Int32) -> (.result: ?Int32) {
    result = input
}

main := () -> () {
    implementation ::= Implementation()
    _ ::= to_virtual<Extractor>(&implementation)
}

Extractor: Abstract = (
    take(.self: &Self, .storage: &Allocation, .input: ?Int32) -> (.result: ?Int32) where {
        transfers(result, input)
        on result ..some { from_storage(result, storage) }
    }
)

Implementation: Type = ()

Implementation implements Extractor

take(.self: &Implementation, .storage: &Allocation, .input: ?Int32) -> (.result: ?Int32) := {
    result = input
}

main() -> () := {
    implementation ::= Implementation()
    _ ::= to_virtual#(Extractor)(&implementation)
}

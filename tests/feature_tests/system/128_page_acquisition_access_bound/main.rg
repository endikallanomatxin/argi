Acquire#(.Provider: Type): Contract = (
    .acquire: (.self: $&Provider) -> (.result: AcquiredStorage) where {
        reads(self)
        owns(result)
        depends_on(result, self)
    }
)
implement Acquire#(Memory) (
    .acquire = (.self: $&Memory) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(acquire_page_storage(.memory = self, .size = 1, .alignment = 1))
    }
)
main := (.system: System) -> () {
    provider ::= Virtual#(Acquire)(system.memory)
}

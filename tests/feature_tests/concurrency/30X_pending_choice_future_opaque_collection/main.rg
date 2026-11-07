read := (.value: &Int32) -> (.result: Int32) { result = value& }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= Virtual#(Allocator)($&allocator_storage)
    value :: Int32 = 42
    tasks ::= unwrap_or_abort(.value = DynamicArray#(?Future#(Int32))(.capacity = 1))
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    entry: ?Future#(Int32) = ..some(.value = ~future)
    push_assume_capacity($&tasks, .value = ~entry)
}

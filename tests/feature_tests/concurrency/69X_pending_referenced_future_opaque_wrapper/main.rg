read := (.value: &Int32) -> (.result: Int32) { result = value& }
store := (.tasks: $&DynamicArray#(Future#(Int32)), .source: $&Future#(Int32)) -> () {
    push_assume_capacity(tasks, .value = ~source&)
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= Virtual#(Allocator)($&allocator_storage)
    value :: Int32 = 42
    tasks ::= unwrap_or_abort(.value = DynamicArray#(Future#(Int32))(.capacity = 1))
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    store(.tasks = $&tasks, .source = $&future)
}

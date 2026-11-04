Work := (.task: Future#(Int32))
read := (.value: &Int32) -> (.result: Int32) { result = value& }
store := (.tasks: $&DynamicArray#(Work), .work: Work) -> () {
    pending ::= ~work
    push_assume_capacity(tasks, .value = ~pending)
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= to_virtual#(Allocator)($&allocator_storage)
    value :: Int32 = 42
    tasks ::= unwrap_or_abort(.value = DynamicArray#(Work)(.capacity = 1))
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    work: Work = (.task = ~future)
    store(.tasks = $&tasks, .work = ~work)
}

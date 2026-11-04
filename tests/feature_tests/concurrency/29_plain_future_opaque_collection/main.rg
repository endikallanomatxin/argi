double := (.value: Int32) -> (.result: Int32) { result = value * 2 }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= to_virtual#(Allocator)($&allocator_storage)
    tasks ::= unwrap_or_abort(.value = DynamicArray#(Future#(Int32))(.capacity = 1))
    future ::= unwrap_or_abort(.value = async#(double)(.args = (.value = 21)))
    _ = unwrap_or_abort(.value = push($&tasks, .value = ~future))
}

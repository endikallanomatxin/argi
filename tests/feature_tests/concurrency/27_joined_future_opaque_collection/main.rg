read := (.value: &Int32) -> (.result: Int32) { result = value& }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= Virtual#(Allocator)($&allocator_storage)
    tasks ::= unwrap_or_abort(.value = DynamicArray#(Future#(Int32))(.capacity = 1))
    {
        value :: Int32 = 42
        future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
        if unwrap_or_abort(.value = await($&future)) != 42 { abort }
        _ = unwrap_or_abort(.value = push($&tasks, .value = ~future))
    }
}

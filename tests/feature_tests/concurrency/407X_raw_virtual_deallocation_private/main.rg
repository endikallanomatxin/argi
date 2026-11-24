main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    release ::= Virtual#(Deallocator)($&allocator)
    empty ::= raw_pointer#(UInt8)(.address = 0).raw
    release._deallocate(.data = empty, .size = 0, .alignment = 1)
}

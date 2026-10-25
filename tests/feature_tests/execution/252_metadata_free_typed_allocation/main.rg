Choice: Type = (..empty, ..number(.value: Int32))

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    booleans ::= unwrap_or_abort(.value = allocate#(.t: Bool)(.self = $&allocator, .count = 2))
    choices ::= unwrap_or_abort(.value = allocate#(.t: Choice)(.self = $&allocator, .count = 3))
    empty ::= unwrap_or_abort(.value = allocate#(.t: Int32)(.self = $&allocator, .count = 0))
    if booleans.size != 2 { abort }
    if choices.size != 3 * size_of(.type = Choice) { abort }
    if empty.size != 0 { abort }
    status_code = 42
}

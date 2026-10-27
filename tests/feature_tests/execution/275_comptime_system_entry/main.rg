answer ::= #run (.system: System) -> (.value: Int32) {
    tracer :: NoopErrorTracer = (.marker = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    assume writer ::= $&system.terminal&.stdout
    assume ffi ::= system.ffi
    assume allocator ::= $&CAllocator(.ffi = ffi)
    text ::= unwrap_or_abort(.value = String(.length = 5))
    if system.page_allocator&.page_size == 0 { abort }
    print("compile-time host\n")
    value = 42
}

defaulted ::= #run (.system: System) -> (.value: Int32 = 42) {}
pair ::= #run (.system: System) -> (.left: Int32, .right: Int32) {
    left = 40
    right = 2
}
selected ::= #run (.system: System) -> (.value: Int32) {
    #if true { value = 42 } #else { value = missing_value }
}

nested ::= #run () -> (.value: Int32) {
    first ::= #run (.system: System) -> (.part: Int32) { part = 40 }
    second ::= #run (.system: System) -> (.part: Int32) { part = 2 }
    value = first + second
}

main := () -> (.status_code: Int32) {
    if defaulted != 42 or pair.left + pair.right != 42 or selected != 42 { abort }
    if nested != 42 { abort }
    status_code = answer
}

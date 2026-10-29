main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    set ::= HashSet#(.key: Int32)()!!!
    insert($&set, .key = 1)!!!
    iterator ::= to_reference_iterator(&set).iterator
    key ::= next($&iterator).value
    remove($&set, .key = &1)
    if key&!= 1 { abort }
    status_code = 0
}

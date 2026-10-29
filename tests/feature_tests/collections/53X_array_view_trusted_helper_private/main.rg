main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    element :: Int32 = 1
    view ::= _trusted_mutable_array_view#(.t: Int32)(.data = $&element, .length = 1000)
    status_code = get(.self = &view, .index = 900).result ..ok
}

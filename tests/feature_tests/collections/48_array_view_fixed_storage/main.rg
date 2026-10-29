main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    values :: [3]Int32 = (4, 5, 6)
    borrowed_view :: MutableArrayView#(Int32) = view(.self = $&values)
    read_view :: ArrayView#(Int32) = view(.self = &values)

    if length(.self = &borrowed_view).count != 3 or length(.self = &read_view).count != 3 {
        status_code = 1
        return
    }
    changed ::= set#(.t: Int32)(.self = $&borrowed_view, .index = 1, .value = 9).result
    if is(.value = changed, .variant = ..error) {
        status_code = 2
        return
    }
    observed ::= get_reference(.self = &read_view, .index = 1).result
    if is(.value = observed, .variant = ..error) {
        status_code = 3
        return
    }
    if observed ..ok&!= 9 {
        status_code = 4
        return
    }
    reduced :: ArrayView#(Int32) = as_readonly(&borrowed_view)
    subrange :: ArrayView#(Int32) = unwrap_or_abort(
        .value = slice(&reduced, .start = 1, .count = 1)
    )
    if unwrap_or_abort(.value = get(&subrange, .index = 0)) != 9 { abort }
    single :: ArrayView#(Int32) = single_array_view(.data = &values[0])
    writable_single :: MutableArrayView#(Int32) = single_mutable_array_view(.data = $&values[0])
    unwrap_or_abort(.value = set($&writable_single, .index = 0, .value = 12))
    if unwrap_or_abort(.value = get(&single, .index = 0)) != 12 { abort }
    status_code = 0
}

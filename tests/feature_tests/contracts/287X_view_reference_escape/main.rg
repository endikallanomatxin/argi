escape := () -> (.result: ArrayView#(.t: Int32)) {
    values :: [2]Int32 = (1, 2)
    result = view(.self = &values)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    escaped ::= escape()
    item ::= unwrap_or_abort(.value = get_reference(.self = &escaped, .index = 0))
}

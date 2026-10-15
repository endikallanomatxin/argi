escape := () -> (.result: ArrayViewRO#(.t: Int32)) {
    values :: [2]Int32 = (1, 2)
    result = view(.array = &values)
}

main := () -> () {
    escaped ::= escape()
    item ::= unwrap_or_abort(.value = get_reference(.self = &escaped, .index = 0))
}

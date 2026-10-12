main := () -> () {
    order ::= Int32OrderPolicy()
    less(.self = &order, .left = 1, .right = 2)
}

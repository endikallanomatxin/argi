main := () -> () {
    policy ::= Int32HashPolicy()
    hash(.self = &policy, .key = 1)
}

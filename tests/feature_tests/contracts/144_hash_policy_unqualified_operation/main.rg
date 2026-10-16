main := () -> () {
    policy ::= StandardHashPolicy()
    hash(.self = &policy, .key = &1)
}

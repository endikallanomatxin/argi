main := () -> () {
    policy ::= StandardHashPolicy()
    HashPolicy#(StandardHashPolicy, Int32).hash(.self = &policy, .key = &1)
}

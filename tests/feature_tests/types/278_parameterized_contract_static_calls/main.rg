check_policy := #(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) (
    .self: &policy, .left: key, .right: key
) -> (.digest: UIntNative, .equal: Bool) {
    left_query ::= HashPolicy#(policy, key).query(self, .key = &left)
    right_query ::= HashPolicy#(policy, key).query(self, .key = &right)
    digest = HashPolicy#(policy, key).hash(.self = self, .key = left_query).hash
    equal = HashPolicy#(
        policy, key
    ).equal(.self = self, .left = left_query, .right = right_query).ok
}

main := () -> (.status_code: Int32 = 0) {
    library := import ("./policy")
    policy ::= library.ConstantPolicy()
    result ::= check_policy(.self = &policy, .left = 1, .right = 2)
    if result.digest != 42 or result.equal { abort }
    same ::= check_policy(.self = &policy, .left = 2, .right = 2)
    if same.equal == false { abort }
}

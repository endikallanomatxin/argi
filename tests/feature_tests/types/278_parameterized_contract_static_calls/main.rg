check_policy#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(.key: key))(.self: &policy, .left: key, .right: key) -> (.digest: UIntNative, .equal: Bool) := {
    digest = hash(.self = self, .key = left).hash
    equal = eql(.self = self, .left = left, .right = right).ok
}
main() -> (.status_code: Int32 = 0) := {
    library := import("./policy")
    policy ::= library.ConstantPolicy()
    result ::= check_policy(.self = &policy, .left = 1, .right = 2)
    if result.digest != 42 or result.equal { abort }
    same ::= check_policy(.self = &policy, .left = 2, .right = 2)
    if same.equal == false { abort }
}

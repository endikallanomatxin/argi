Policy: Type = ()

implement HashPolicy#(Policy, Int32) (
    .hash = (.self: &Policy, .key: &Int32) -> (.hash: UIntNative) { hash = 0 }
    .eql  = (.self: &Policy, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = left&== right&
    }
)

main(.system: System) -> () := {
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: Int32, .value: Int32, .policy: Policy)())
}

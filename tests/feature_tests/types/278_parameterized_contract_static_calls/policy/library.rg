ConstantPolicy : Type = ()
ConstantPolicy implements ImplicitlyCopyable
ConstantPolicy implements HashPolicy#(.key: Int32)
hash(.self: &ConstantPolicy, .key: Int32) -> (.hash: UIntNative) := { hash = 42 }
eql(.self: &ConstantPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left == right }

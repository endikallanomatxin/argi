ConstantPolicy: Type = ()

ConstantPolicy implements ImplicitlyCopyable
implement HashPolicy#(ConstantPolicy, Int32)(

    .hash = (.self: &ConstantPolicy, .key: Int32) -> (.hash: UIntNative) { hash = 42 }
    .eql  = (.self: &ConstantPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) {
        ok = left == right
    }
)

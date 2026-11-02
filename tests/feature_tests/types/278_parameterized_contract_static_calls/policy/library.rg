ConstantPolicy: Type = ()

implement ImplicitlyCopyable#(ConstantPolicy) ()

implement HashPolicy#(ConstantPolicy, Int32) (
    .Query : Type = &Int32
    .query = (.self: &ConstantPolicy, .key: &Int32) -> (.query: Query) { query = key }

    .hash  = (.self: &ConstantPolicy, .key: &Int32) -> (.hash: UIntNative) { hash = 42 }
    .equal = (.self: &ConstantPolicy, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = left&== right&
    }
)

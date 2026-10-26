InfalliblyCopyable<.Value: Type>: Contract = (
    .copy : (.self: &Value) -> (.value: Value)
)

implement<.t: Type: ImplicitlyCopyable> InfalliblyCopyable<t> (
    .copy = (.self: &t) -> (.value: t) { value = self&}
)

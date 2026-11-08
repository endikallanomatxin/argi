Offset#(.Provider: Type): Contract = (
    .get: (.self: &Provider, .base: &Int32, .elements: UIntNative) -> (.result: &Int32)
        where { refers_to(result, base) }
)
shift := (.base: &Int32, .elements: UIntNative) -> (.result: &Int32) {
    retyped ::= trusted_reinterpret_reference#(.from: Int32, .to: UInt32)(.base = base)
    result = trusted_reinterpret_reference#(.from: UInt32, .to: Int32)(.base = retyped)
}
Provider: Type = ()
implement Offset#(Provider) (
    .get = (.self: &Provider, .base: &Int32, .elements: UIntNative) -> (.result: &Int32) {
        result = shift(.base = base, .elements = elements)
    }
)
main := () -> () {
    provider ::= Provider()
    values: [2]Int32 = (7, 9)
    handle ::= Virtual#(Offset)(&provider)
    result ::= Offset#().get(&handle, .base = &values[0], .elements = 1)
    _ = result&
}

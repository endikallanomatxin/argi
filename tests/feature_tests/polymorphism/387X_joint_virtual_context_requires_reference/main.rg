CopyBetween#(.Source: Type, .Destination: Type): Contract = (
    .copy: (.destination: Destination, .count: UIntNative, .source: Source) -> () where {}
)
Context := (.Destination: $&Int32, .Source: Int32)
main := () -> () {
    value :: Int32 = 1
    context ::= Context(.Destination = $&value, .Source = 42)
    handle ::= Virtual#(CopyBetween)(&context)
    _ = handle
}

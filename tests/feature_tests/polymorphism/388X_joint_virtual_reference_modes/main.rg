CopyBetween#(.Source: Type, .Destination: Type): Contract = (
    .copy: (.destination: Destination, .count: UIntNative, .source: Source) -> () where {}
)
implement CopyBetween#(&Int32, $&Int32) (
    .copy = (.destination: $&Int32, .count: UIntNative, .source: &Int32) -> () {
        if count != 0 { destination& = source& }
    }
)
Context := (.Destination: &Int32, .Source: $&Int32)
main := () -> () {
    source :: Int32 = 1
    destination ::= 0 | convert#(.to: Int32)(_)
    context ::= Context(.Destination = &destination, .Source = $&source)
    handle ::= Virtual#(CopyBetween)(&context)
    _ = handle
}

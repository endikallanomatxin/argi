PairView#(.Left: Type, .Right: Type): Contract = (
    .left: (.right: Right, .left: Left) -> (.reference: Left) where depends_on(reference, left)
)
implement PairView#(&Int32, $&Int32) (
    .left = (.right: $&Int32, .left: &Int32) -> (.reference: &Int32) {
        reference = left
    }
)
Context := (.Right: $&Int32, .Left: &Int32)
main := () -> () {
    left :: Int32 = 1
    right :: Int32 = 0
    context ::= Context(.Right = $&right, .Left = &left)
    handle ::= Virtual#(PairView)(&context)
    _ = handle
}

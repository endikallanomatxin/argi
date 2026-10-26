drops :: Int32 = 0

Owner := (.value: Int32)

Witness: Type = ()

implement Deinit<Owner> (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)

implement Init<Witness, (.pair: (.left: $&Owner, .right: &Owner))> (
    .Result : Type = Witness
    .init   = (.args: (.pair: (.left: $&Owner, .right: &Owner))) -> (.result: Result) {
        Deinit<Owner>.deinit(.self = args.pair.left)
        result = ()
    }
)

main := () -> () {
    left ::= Owner(.value = 1)
    right ::= Owner(.value = 2)
    witness ::= Witness(.pair = (.left = $&left, .right = &right))
    observed ::= left.value
}

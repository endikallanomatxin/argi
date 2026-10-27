drops :: Int32 = 0

Owner := (.value: Int32)

Witness: Type = ()

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)

WitnessInitArgs: Type = (.pair: (.left: $&Owner, .right: &Owner))

implement Init#(Witness, WitnessInitArgs) (
    .Result : Type = Witness

    .init = WitnessInitArgs -> (.result: Result) {
        Deinit#(Owner).deinit(.self = pair.left)
        result = ()
    }
)

main := () -> () {
    left ::= Owner(.value = 1)
    right ::= Owner(.value = 2)
    witness ::= Witness(.pair = (.left = $&left, .right = &right))
    observed ::= left.value
}

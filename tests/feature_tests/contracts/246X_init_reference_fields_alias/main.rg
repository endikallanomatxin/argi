Owner := (.value: Int32)

Witness: Type = ()

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

WitnessInitArgs: Type = (.left: $&Owner, .right: $&Owner)

implement Init#(Witness, WitnessInitArgs) (
    .Result : Type = Witness

    .init = WitnessInitArgs -> (.result: Result) {
        Deinit#(Owner).deinit(.self = left)
        Deinit#(Owner).deinit(.self = right)
        result = ()
    }
)

main := () -> () {
    value ::= Owner(.value = 1)
    witness ::= Witness(.left = $&value, .right = $&value)
}

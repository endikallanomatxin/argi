Owner := (.value: Int32)

Witness: Type = ()

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

implement Init#(Witness) (
    .init = (.left: $&Owner, .right: $&Owner) -> (.result: Witness) {
        Deinit#(Owner).deinit(.self = left)
        Deinit#(Owner).deinit(.self = right)
        result = ()
    }
)

main := () -> () {
    value ::= Owner(.value = 1)
    witness ::= Witness(.left = $&value, .right = $&value)
}

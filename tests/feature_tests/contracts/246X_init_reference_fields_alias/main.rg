Owner := (.value: Int32)

Witness: Type = ()

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

implement Init#(Witness, (.left: $&Owner, .right: $&Owner)) (
    .Result : Type = Witness
    .init   = (.args: (.left: $&Owner, .right: $&Owner)) -> (.result: Result) {
        Deinit#(Owner).deinit(.self = args.left)
        Deinit#(Owner).deinit(.self = args.right)
        result = ()
    }
)

main := () -> () {
    value ::= Owner(.value = 1)
    witness ::= Witness(.left = $&value, .right = $&value)
}

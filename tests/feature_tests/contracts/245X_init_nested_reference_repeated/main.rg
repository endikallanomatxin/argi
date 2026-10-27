drops :: Int32 = 0

Owner := (.value: Int32)

Witness: Type = ()

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { drops = drops + 1 }
)

implement Init#(Witness) (
    .init = (.pair: (.left: $&Owner, .right: &Owner)) -> (.result: Witness) {
        Deinit#(Owner).deinit(.self = pair.left)
        result = ()
    }
)

repeat := (.left: $&Owner, .right: &Owner) -> () {
    first ::= Witness(.pair = (.left = left, .right = right))
    second ::= Witness(.pair = (.left = left, .right = right))
}

main := () -> () {
    left ::= Owner(.value = 1)
    right ::= Owner(.value = 2)
    repeat(.left = $&left, .right = &right)
}

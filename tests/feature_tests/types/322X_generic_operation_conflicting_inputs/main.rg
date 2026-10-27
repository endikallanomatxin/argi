Pair#(.Owner: Type): Contract = (
    .pair : #(.Value: Type) (.left: Value, .right: Value) -> (.result: Bool)
)

Owner := (.unused: Bool)

implement Pair#(Owner) (
    .pair = #(.Item: Type) (.left: Item, .right: Item) -> (.result: Bool) { result = true }
)

main := () -> () {
    value: Bool = Pair#(Owner).pair(.left = true, .right = 42).result
}

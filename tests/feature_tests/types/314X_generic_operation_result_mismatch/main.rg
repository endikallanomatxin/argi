Identity#(.Owner: Type): Contract = (
    .apply : #(.Value: Type) (.value: Value) -> (.result: Value)
)

Owner := (.flag: Bool)

wrong := #(.Item: Type) (.value: Item) -> (.result: Int32) { result = 42 }

implement Identity#(Owner) (.apply = wrong)

main := () -> () {
    result: Bool = Identity#(Owner).apply(.value = true).result
}

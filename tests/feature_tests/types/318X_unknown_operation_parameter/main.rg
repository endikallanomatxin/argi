Identity#(.Owner: Type): Contract = (
    .apply: <.Value: Type> (.value: Value) -> (.result: Value)
)
Owner := (.flag: Bool)
implement Identity#(Owner) (
    .apply = <.Item: Type> (.value: Item) -> (.result: Item) { result = value }
)
main := () -> () {
    result: Bool = Identity<Owner>.apply<.Missing: Bool>(.value = true).result
}

Owner := (.flag: Bool)

Arguments := <.Item: Type> (.value: Item)

Factory#(.Participant: Type): Contract = (
    .Args : <.Item: Type> Type
    .make : <.Item: Type> Args<Item> -> (.result: Item)
)

implement Factory#(Owner) (
    .Args : <.Item: Type> Type = Arguments
    .make = <.Value: Type> (.value: Value) -> (.result: Value) {
        result = value
    }
)

known ::= #run () -> (.result: Bool) {
    result = Factory<Owner>.make<Bool>(.value = true).result
}

main := () -> () {
    if Factory<Owner>.make<Bool>(.value = true).result {} else { abort }
    number: Int32 = Factory<Owner>.make<Int32>(.value = 42).result
    if number != 42 { abort }
    if known {} else { abort }
}

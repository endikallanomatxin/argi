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

projected_flag := <.Participant: Type> (.args: Factory<Participant>.Args<Bool>) -> (
    .result : Bool
) {
    result = args.value
}

known ::= #run () -> (.result: Bool) {
    args: Factory<Owner>.Args<Bool> = (.value = true)
    result = Factory<Owner>.make<Bool>(.value = args.value).result
}

main := () -> () {
    if Factory<Owner>.make<Bool>(.value = true).result {} else { abort }
    number: Int32 = Factory<Owner>.make<Int32>(.value = 42).result
    if number != 42 { abort }
    if known {} else { abort }
    projected: Factory<Owner>.Args<Bool> = (.value = true)
    same: Arguments<Bool> = projected
    if same.value {} else { abort }
    if projected_flag<Owner>(.args = projected).result {} else { abort }
}

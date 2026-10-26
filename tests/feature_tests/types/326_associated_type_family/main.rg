Owner := (.flag: Bool)

Arguments := <.Item: Type> (.value: Item)

Factory<.Participant: Type>: Contract = (
    .Args : <.Item: Type> Type
    .make : <.Item: Type> Args<Item> -> (.result: Item)
)

implement Factory<Owner> (
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
    owner: Owner = (.flag = true)
    if InlineFactory<Owner>.get_flag<Bool>(.owner = &owner, .value = true).result {
    } else {
        abort
    }
    result = Factory<Owner>.make<Bool>(.value = args.value).result
}

main := () -> () {
    owner: Owner = (.flag = true)
    if InlineFactory<Owner>.get_flag<Bool>(.owner = &owner, .value = true).result {
    } else {
        abort
    }
    if Factory<Owner>.make<Bool>(.value = true).result {} else { abort }
    number: Int32 = Factory<Owner>.make<Int32>(.value = 42).result
    if number != 42 { abort }
    if known {} else { abort }
    projected: Factory<Owner>.Args<Bool> = (.value = true)
    same: Arguments<Bool> = projected
    if same.value {} else { abort }
    inline_args: InlineFactory<Owner>.Args<Int32> = (.owner = &owner, .value = 42)
    if inline_args.value != 42 { abort }
    if InlineFactory<Owner>.get_flag<Int32>(
        .owner = inline_args.owner, .value = inline_args.value
    ).result {
    } else {
        abort
    }
    if projected_flag<Owner>(.args = projected).result {} else { abort }
}

InlineFactory<.Participant: Type>: Contract = (
    .Args     : <.Item: Type> Type
    .get_flag : <.Item: Type> Args<Item> -> (.result: Bool)
)

implement<.Participant: Type> InlineFactory<Participant> (
    .Args     : <.Item: Type> Type = <.Item: Type> (.owner: &Participant, .value: Item)
    .get_flag = <.Value: Type> (.owner: &Participant, .value: Value) -> (.result: Bool) {
        result = owner&.flag
    }
)

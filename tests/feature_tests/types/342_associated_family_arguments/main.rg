Owner := (.flag: Bool)

Arguments := <.Item: Type> (.value: Item)

Factory<.Participant: Type>: Contract = (
    .Args    : <.Item: Type> Type
    .Element : Type
    .count   : Int
)

implement Factory<Owner> (
    .Args    : <.Item: Type> Type = Arguments
    .Element : Type               = Int32
    .count   : Int                = 2
)

make := <.Family: <.Item: Type> Type> (.value: Int32) -> (.result: Family<Int32>) {
    result = (.value = value)
}

forward := <.Participant: Type> (.value: Int32) -> (.result: Int32) {
    args ::= make<.Family = Factory<Participant>.Args>(.value = value)
    result = args.value
}

compute := () -> (.result: Int32) {
    args ::= make<.Family = Factory<Owner>.Args>(.value = 42)
    same: Arguments<Int32> = args
    typed: Array<.n = Factory<Owner>.count, .t: Factory<Owner>.Element> = (same.value, 0)
    if typed[0] != 42 { abort }
    result = forward<Owner>(.value = same.value).result
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = compute()
}

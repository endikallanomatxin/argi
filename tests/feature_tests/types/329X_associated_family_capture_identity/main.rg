First := (.flag: Bool)

Second := (.flag: Bool)

Factory#(.Participant: Type): Contract = (
    .Args : <.Item: Type> Type
)

implement#(.Participant: Type) Factory#(Participant) (
    .Args : <.Item: Type> Type = <.Item: Type> (.value: Item)
)

main := () -> () {
    first: Factory<First>.Args<Bool> = (.value = true)
    second: Factory<Second>.Args<Bool> = first
}

Owner := (.flag: Bool)

Arguments := (.value: Bool)

Factory#(.Participant: Type): Contract = (
    .Args : Type
)

implement Factory#(Owner) (
    .Args : Type = Arguments
)

main := () -> () {
    value: Factory<Owner>.Args<Bool> = (.value = true)
}

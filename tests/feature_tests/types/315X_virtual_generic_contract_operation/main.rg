Readable#(.Participant: Type): Contract = (
    .read : #(.Value: Type) (.owner: &Participant, .value: Value) -> (.result: Value)
)

Owner := (.flag: Bool)

implement Readable#(Owner) (
    .read = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Item) { result = value }
)

main := () -> () {
    owner: Owner = (.flag = true)
    handle ::= to_virtual#(.contract: Readable)(.value = &owner)
}

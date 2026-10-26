Owner := (.flag: Bool)

First#(.Participant: Type): Contract = (
    .choose : <.Item: Type> (.owner: &Participant, .value: Item) -> (.result: Bool)
)

Second#(.Participant: Type): Contract = (
    .choose : <.Item: Type> (.owner: &Participant, .value: Item) -> (.result: Bool)
)

implement First#(Owner) (
    .choose = <.Item: Type> (.owner: &Owner, .value: Item) -> (.result: Bool) {
        result = owner&.flag
    }
)

implement Second#(Owner) (
    .choose = <.Item: Type> (.owner: &Owner, .value: Item) -> (.result: Bool) {
        result = owner&.flag
    }
)

main := () -> () {
    owner: Owner = (.flag = true)
    if choose<Bool>(.owner = &owner, .value = true).result {} else { abort }
}

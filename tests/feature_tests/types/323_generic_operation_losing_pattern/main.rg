Same#(.Participant: Type): Contract = (
    .combine : <.Value: Type> (.owner: &Participant, .left: Value, .right: Value) -> (
        .result : Bool
    )
)

Different#(.Participant: Type): Contract = (
    .combine : <.Left: Type,
    .Right   : Type> (.owner: &Participant, .left: Left, .right: Right) -> (.result: Bool)
)

Owner := (.unused: Bool)

implement Same#(Owner) (
    .combine = <.Item: Type> (.owner: &Owner, .left: Item, .right: Item) -> (.result: Bool) {
        result = false
    }
)

implement Different#(Owner) (
    .combine = <.A: Type,
    .B       : Type> (.owner: &Owner, .left: A, .right: B) -> (.result: Bool) { result = true }
)

computed ::= #run () -> (.result: Bool) {
    owner: Owner = (.unused = false)
    result = combine(.owner = &owner, .left = true, .right = 42).result
}

main := () -> () {
    owner: Owner = (.unused = false)
    if combine(.owner = &owner, .left = true, .right = 42).result {} else { abort }
    if computed {} else { abort }
}

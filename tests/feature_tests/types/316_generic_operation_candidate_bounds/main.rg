Allowed#(.Value: Type): Contract = ()
implement Allowed#(Bool) ()

Constrained#(.Participant: Type): Contract = (
    .route: <.Value: Type: Allowed#(Value)> (.owner: &Participant, .value: Value) -> (.result: Bool)
)
Open#(.Participant: Type): Contract = (
    .route: <.Value: Type> (.owner: &Participant, .value: Value) -> (.result: Bool)
)
Owner := (.flag: Bool)
implement Constrained#(Owner) (
    .route = <.Item: Type> (.owner: &Owner, .value: Item) -> (.result: Bool) { result = true }
)
implement Open#(Owner) (
    .route = <.Item: Type> (.owner: &Owner, .value: Item) -> (.result: Bool) { result = false }
)
computed ::= #run () -> (.result: Bool) {
    owner: Owner = (.flag = true)
    result = route(.owner = &owner, .value = 42).result
}
main := () -> () {
    owner: Owner = (.flag = true)
    if route(.owner = &owner, .value = 42).result { abort }
    if Constrained#(Owner).route(.owner = &owner, .value = true).result {} else { abort }
    if computed { abort }
}

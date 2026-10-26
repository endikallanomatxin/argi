Identity#(.Owner: Type): Contract = (
    .flag: (.owner: &Owner) -> (.result: Bool)
    .apply: <.Value: Type> (.value: Value) -> (.result: Value) where { depends_on(result, value) }
)

Owner := (.flag: Bool)

implement Identity#(Owner) (
    .flag = (.owner: &Owner) -> (.result: Bool) { result = owner&.flag }
    .apply = <.Item: Type> (.value: Item) -> (.result: Item) {
        result = value
    }
)

AliasIdentity#(.Participant: Type): Contract = (
    .alias_apply: <.Value: Type> (.value: Value) -> (.result: Value)
)

ordinary_identity := <.Item: Type> (.value: Item) -> (.result: Item) { result = value }
implement AliasIdentity#(Owner) (.alias_apply = ordinary_identity)

Factory#(.Participant: Type): Contract = (
    .Result: Type
    .make: <.Value: Type = Bool> (.owner: &Participant, .value: Value = true) -> (.result: Result)
)

implement#(.Participant: Type) Factory#(Participant) (
    .Result: Type = Bool
    .make = <.Item: Type> (.owner: &Participant, .value: Item) -> (.result: Result) {
        result = owner&.flag
    }
)

computed ::= #run () -> (.result: Bool) {
    result = Identity#(Owner).apply(.value = true).result
}

main := () -> () {
    owner: Owner = (.flag = true)
    if Identity#(Owner).flag(.owner = &owner).result {} else { abort }
    if Factory#(Owner).make(.owner = &owner, .value = 42).result {} else { abort }
    if make(.owner = &owner, .value = true).result {} else { abort }
    if make(.owner = &owner).result {} else { abort }
    if Identity#(Owner).apply(.value = true).result {} else { abort }
    number: Int32 = Identity#(Owner).apply(.value = 42).result
    if number != 42 { abort }
    if AliasIdentity#(Owner).alias_apply(.value = true).result {} else { abort }
    if computed {} else { abort }
}

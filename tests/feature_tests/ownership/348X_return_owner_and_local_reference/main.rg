Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

escape() -> (.result: (.owner: Resource, .reference: &Int32)) := {
    owner ::= Resource(7)
    reference ::= &owner.value
    result = (.owner = ~owner, .reference = reference)
}

main() -> () := {
    escaped ::= escape()
}

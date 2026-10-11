Resettable: Abstract = (
    reset(.self: $&Self) -> () where {}
)

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

Cell: Type = (.resource: Resource)

Cell implements Resettable

reset(.self: $&Cell) -> () := {
    deinit($&self&.resource)
}

main() -> () := {
    cell ::= Cell(Resource(42))
    handle ::= to_virtual#(Resettable)($&cell)
}

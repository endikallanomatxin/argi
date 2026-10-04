Readable#(.item: Type): Abstract = (
    read(.self: &Self) -> (.value: &item)
)

Box: Type = (.value: Int32)

Box deinit(.self: $&Box) -> () := {}

Box implements Readable#(.item: Int32)

read(.self: &Box) -> (.value: &Int32) := { value = &self&.value }

consume(.input: &Virtual#(.abstract: Readable#(.item: Int32))) -> (.value: &Int32) := {
    value = read(.self = input)
}

main() -> () := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: Readable#(.item: Int32))(.value = &box)
    reference ::= consume(.input = &handle).value
    deinit(.self = $&box)
    observed ::= reference&
}

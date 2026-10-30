Storage#(.Receiver: Type): Contract = (
    .replace : (.self: $&Receiver, .value: &Int32) -> () where {}
)

Cell := (.reference: &Int32)

implement Storage#(Cell) (
    .replace = (.self: $&Cell, .value: &Int32) -> () { self&.reference = value }
)

main := () -> () {

    first: Int32 = 1
    second: Int32 = 2
    cell ::= Cell(.reference = &first)
    erased ::= to_virtual#(.contract: Storage)(.value = $&cell)
    Storage#().replace($&erased, .value = &second)
}

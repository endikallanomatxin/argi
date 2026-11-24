Read#(.R: Type): Contract = (
    .read: (.other: $&Cell, .receiver: R) -> (.value: Int32) where reads(receiver)
    .read_first: (.receiver: R, .other: $&Cell) -> (.value: Int32) where reads(receiver)
)
Cell := (.value: Int32)
implement Read#($&Cell) (
    .read = (.other: $&Cell, .receiver: $&Cell) -> (.value: Int32) { value = receiver&.value }
    .read_first = (.receiver: $&Cell, .other: $&Cell) -> (.value: Int32) { value = receiver&.value }
)
implement Read#(&Cell) (
    .read = (.other: $&Cell, .receiver: &Cell) -> (.value: Int32) { value = receiver&.value }
    .read_first = (.receiver: &Cell, .other: $&Cell) -> (.value: Int32) { value = receiver&.value }
)
forward := (.reader: Virtual#(Read)) -> (.result: Virtual#(Read)) {
    result = reader
}
main := () -> () {
    other ::= Cell(99)
    first ::= Cell(1)
    second ::= Cell(2)
    mutable_reader ::= forward(Virtual#(Read)($&first)).result
    readonly_reader ::= forward(Virtual#(Read)(&second)).result
    if mutable_reader.read($&other).value != 1 { abort }
    if readonly_reader.read($&other).value != 2 { abort }
    if mutable_reader.read_first($&other).value != 1 { abort }
    if readonly_reader.read_first($&other).value != 2 { abort }
}

Readable <.T: Type >: Contract = (
    .read : (.source: &T) -> (.value: Int32)
)
Writable <.T: Type >: Contract = (
    Readable < T >
    .write : (.target: $&T, .value: Int32) -> ()
)
Cell := (.value: Int32)
implement Readable < Cell > (
    .read = (.source: &Cell) -> (.value: Int32) { value = source&.value }
)
implement Writable < Cell > (
    .write = (.target: $&Cell, .value: Int32) -> () { target&.value = value }
)
main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(.value = 1)
    write($&cell, .value = 42)
    if read(&cell).value != 42 { abort }
}

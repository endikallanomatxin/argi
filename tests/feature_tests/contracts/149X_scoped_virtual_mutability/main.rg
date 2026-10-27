Input#(.Stream: Type): Contract = (
    .read_byte : (.self: $&Stream) -> (.result: UInt8) where {}
)

Cursor := (.value: UInt8 = 7)

implement Input#(Cursor) (
    .read_byte = (.self: $&Cursor) -> (.result: UInt8) { result = self&.value }
)

main := () -> () {
    stream ::= Cursor()
    erased ::= to_virtual#(.contract: Input)(.value = &stream)
}

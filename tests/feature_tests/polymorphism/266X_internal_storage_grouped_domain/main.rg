Protocol#(.Participant: Type): Contract = (
    .contents: Region#(Participant)
    .clear : (.self: $&Participant) -> () where empties(self.contents)
)

Storage := (.first: Int32, .second: Int32)

implement Protocol#(Storage) (
    .contents = region(self.first, self.second),
    .clear = _impl_clear_Storage)

_impl_clear_Storage := (.self: $&Storage) -> () {}

main := () -> () {
    storage ::= Storage(1, 2)
    value ::= Virtual#(Protocol)($&storage)
}

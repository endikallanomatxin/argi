Protocol#(.Participant: Type): Contract = (
    .contents: Region#(Participant)
    .clear : (.self: $&Participant) -> () where empties(self.contents)
)

Storage := (.contents: $&Int32)

implement Protocol#(Storage) (
    .contents = region(self.contents),
    .clear = _impl_clear_Storage)

_impl_clear_Storage := (.self: $&Storage) -> () {}

main := () -> () {
    contents :: Int32 = 0
    storage ::= Storage($&contents)
    value ::= to_virtual#(Protocol)($&storage)
}

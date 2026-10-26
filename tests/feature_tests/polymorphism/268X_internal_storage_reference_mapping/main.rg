Protocol<.Participant: Type>: Contract = (
    domain contents
    .clear : (.self: $&Participant) -> () where empties(self.contents)
)

Storage := (.contents: $&Int32)

implement Protocol<Storage> (.clear = _impl_clear_Storage) where { contents(self.contents) }

_impl_clear_Storage := (.self: $&Storage) -> () {}

main := () -> () {
    contents :: Int32 = 0
    storage ::= Storage($&contents)
    value ::= to_virtual<Protocol>($&storage)
}

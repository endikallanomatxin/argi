Protocol<.Participant: Type>: Contract = (
    domain contents
    .clear : (.self: $&Participant) -> () where empties(self.contents)
)

Storage := (.first: Int32, .second: Int32)

implement Protocol<Storage> (.clear = _impl_clear_Storage) where {
    contents(self.first, self.second)
}

_impl_clear_Storage := (.self: $&Storage) -> () {}

main := () -> () {
    storage ::= Storage(1, 2)
    value ::= to_virtual<Protocol>($&storage)
}

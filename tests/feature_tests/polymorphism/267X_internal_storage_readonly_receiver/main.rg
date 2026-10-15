Protocol#(.Participant: Type): Contract = (
    domain contents
    .clear: (.self: &Participant) -> () where empties(self.contents)
)
Storage: Type = (.first: Int32)
implement Protocol#(Storage) (.clear = _impl_clear_Storage) where { contents(self.first) }
_impl_clear_Storage := (.self: &Storage) -> ()  {}
main() -> () := {
    storage ::= Storage(1)
    value ::= to_virtual#(Protocol)(&storage)
}

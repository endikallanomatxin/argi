Protocol: Abstract = (
    domain contents
    clear(.self: $&Self) -> () where empties(self.contents)
)
Storage: Type = (.first: Int32, .second: Int32)
Storage implements Protocol where { contents(self.first, self.second) }
clear(.self: $&Storage) -> () := {}
main() -> () := {
    storage ::= Storage(1, 2)
    value ::= to_virtual#(Protocol)($&storage)
}

Protocol: Abstract = (
    domain contents
    clear(.self: $&Self) -> () where empties(self.contents)
)
Storage: Type = (.contents: $&Int32)
Storage implements Protocol where { contents(self.contents) }
clear(.self: $&Storage) -> () := {}
main() -> () := {
    contents :: Int32 = 0
    storage ::= Storage($&contents)
    value ::= to_virtual#(Protocol)($&storage)
}

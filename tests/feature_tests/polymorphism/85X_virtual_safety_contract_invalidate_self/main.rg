Editor: Abstract = (
    edit(.self: $&Self) -> () where invalidates(self)
)

Cell: Type = (.unused: Int32)

Cell implements Editor

edit(.self: $&Cell) -> () := {}

main() -> () := {
    cell ::= Cell(0)
    editor ::= to_virtual#(Editor)($&cell)
}

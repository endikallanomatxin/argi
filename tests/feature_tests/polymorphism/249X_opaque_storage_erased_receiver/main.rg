Drain: Abstract = (
    drain(.self: $&Self) -> () where empties(self)
)

Cell: Type = ()

Cell implements Drain

drain(.self: $&Cell) -> () := { trusted_opaque_mark_empty(self) }

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Drain)($&cell)
}

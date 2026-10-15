Drain#(.Participant: Type): Contract = (
    .drain: (.self: $&Participant) -> () where empties(self)
)

Cell: Type = ()

implement Drain#(Cell) (.drain = _impl_drain_Cell)

_impl_drain_Cell := (.self: $&Cell) -> ()  { trusted_opaque_mark_empty(self) }

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Drain)($&cell)
}

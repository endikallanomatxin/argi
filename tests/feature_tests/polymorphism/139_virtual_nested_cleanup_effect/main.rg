Action#(.Participant: Type): Contract = (
    .run: (.self: &Participant, .target: $&Int32) -> () where { invalidates(target) }
)

Cell: Type = (.unused: Int32)

implement Action#(Cell) (.run = _impl_run_Cell)

Change: Type = (.target: $&Int32)

implement Deinit#(Change) (
    .deinit = (.self: $&Change) -> () {
        self&.target&= 42
    }
)

_impl_run_Cell := (.self: &Cell, .target: $&Int32) -> ()  {
    if true {
        discarded :: ?Change = ..some(.value = Change(target))
    }
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    action ::= to_virtual#(Action)(&cell)
    value :: Int32 = 0

    run(&action, $&value)
    if value != 42 { status_code = 1 }
}

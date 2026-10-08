Action: Abstract = (
    run(.self: &Self, .target: $&Int32) -> () where {}
)

Cell: Type = (.unused: Int32)

Cell implements Action

Change: Type = (.target: $&Int32)

Change deinit(.self: $&Change) -> () := { self&.target&= 42 }

run(.self: &Cell, .target: $&Int32) -> () := {
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

Source: Abstract = (
    get(.self: &Self) -> (.count: Int32, .first: ?&Int32, .second: ?&Int32) where {
        on first ..some { depends_on(first, self) }
        on first ..none {}
        on second ..some { depends_on(second, self) }
        on second ..none {}
    }
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell) -> (.count: Int32, .first: ?&Int32, .second: ?&Int32) := {
    count = 2
    first = ..some(.value = &self&.value)
    second = ..some(.value = &self&.value)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
    values ::= get(&source)

    if values.count != 2 { status_code = 1 }
    match values.first {
        ..some reference { if reference.value&!= 42 { status_code = 2 } }
        ..none { status_code = 3 }
    }
    match values.second {
        ..some reference { if reference.value&!= 42 { status_code = 4 } }
        ..none { status_code = 5 }
    }
}

Source: Abstract = (
    get(.self: &Self, .other: &Int32) -> (.count: Int32, .result: ?&Int32) where {
        on result ..some { depends_on(result, self) }
        on result ..none {}
    }
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell, .other: &Int32) -> (.count: Int32, .result: ?&Int32) := {
    count = 1
    result = ..some(.value = other)
}

main() -> () := {
    cell ::= Cell(42)
    other :: Int32 = 7
    source ::= to_virtual#(Source)(&cell)
    values ::= get(&source, &other)
}

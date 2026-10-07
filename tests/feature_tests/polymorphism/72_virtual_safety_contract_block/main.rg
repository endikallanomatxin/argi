Source: Abstract = (
    get(.self: &Self, .other: &Int32) -> (.first: &Int32, .second: &Int32)
    where {
        depends_on(first, self)
        depends_on(second, other)
    }
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell, .other: &Int32) -> (.first: &Int32, .second: &Int32) := {
    first = &self&.value
    second = other
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(40)
    other :: Int32 = 2
    source ::= to_virtual#(Source)(&cell)
    values ::= get(&source, &other)

    if values.first&+ values.second&!= 42 {
        status_code = 1
    }
}

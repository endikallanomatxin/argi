Source#(.item: Type): Abstract = (
    get(.self: &Self) -> (.value: item) where {}
)

Cell: Type = (.value: Int32)

Other: Type = (.value: Int32)

Cell implements Source#(Int32)
Other implements Source#(Int32)

get(.self: &Cell) -> (.value: Int32) := {
    value = self&.value
}

get(.self: &Other) -> (.value: Int32) := {
    value = self&.value + 1
}

read_source(.source: &Virtual#(Source#(Int32))) -> (.value: Int32) := {
    value = get(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    other ::= Other(41)
    first ::= to_virtual#(Source#(Int32))(&cell)
    second ::= to_virtual#(Source#(Int32))(&other)

    if read_source(&first) != 42 or read_source(&second) != 42 {
        status_code = 1
    }
}

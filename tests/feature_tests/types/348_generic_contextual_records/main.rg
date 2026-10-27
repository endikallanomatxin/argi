Cell := #(.T: Type) (.value: T)
Args := (.cell: Cell#(Int32))

read := Args -> (.value: Int32) { value = cell.value }

make := #(.T: Type) (.value: T) -> (.result: Cell#(T)) {
    local: Cell#(T) = (.value = value)
    result = (.value = local.value)
}

known ::= #run () -> (.result: Int32) {
    cell ::= make(42)
    result = cell.value
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= make(42)
    if cell.value != 42 or known != 42 { status_code = 1 }
    if read(.cell = (.value = 42)) != 42 { status_code = 2 }
}

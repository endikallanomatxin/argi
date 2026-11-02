Cell := #(.T: Type) (.value: T)

implement#(.T: Type: ImplicitlyCopyable) ImplicitlyCopyable#(Cell#(T)) ()

BuildCell#(.Target: Type): Contract = (.Result: Type, .build_cell: _)

implement#(.T: Type) BuildCell#(Cell#(T)) (
    .Result     : Type = Cell#(T)
    .build_cell = (.value: T) -> (.result: Result) { result = (.value = value) }
)

Aliased#(.Target: Type): Contract = (.alias_value: _)

identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

implement Aliased#(Int32) (.alias_value = identity)

main := () -> (.status_code: Int32 = 0) {
    known ::= #run () -> (.result: Bool) {
        cell ::= build_cell(true)
        result = cell.value
    }
    first ::= build_cell(42)
    second ::= build_cell(7)
    first = second
    if first.value != 7 or known == false { status_code = 1 }
    if alias_value(42) != 42 or alias_value#(.T: Int32)(42) != 42 { status_code = 2 }
}

Readable#(.T: Type): Contract = (
    .read: (.value: &T) -> (.result: Bool)
)

Cell := (.flag: Bool)
Inputs := <.T: Type> (.value: &T, .fallback: Bool = false)
Output := (.result: Bool)

read_cell := <.T: Type> Inputs<T> -> Output {
    result = value&.flag or fallback
}

implement Readable#(Cell) (.read = read_cell)

computed ::= #run () -> (.result: Bool) {
    cell: Cell = (.flag = true)
    result = Readable#(Cell).read(.value = &cell).result
}

main := () -> () {
    cell: Cell = (.flag = true)
    if Readable#(Cell).read(.value = &cell).result {} else { abort }
    if computed {} else { abort }
}

Cell := (.value: Int32)

Reset<.T: Type>: Contract = (.reset: (.value: $&T) -> ())

implement Reset<Cell> (
    .reset = (.value: $&Cell) -> () { value&.value = 0 }
)

reset_value := <.T: Type> (.value: $&T) -> () { Reset<T>.reset(value) }

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(7)
    Reset<Cell>.reset($&cell)
    if cell.value != 0 { abort }
    cell.value = 9
    reset_value<Cell>($&cell)
    if cell.value != 0 { abort }
}

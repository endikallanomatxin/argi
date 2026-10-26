Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Cell := <.T: Type> (.value: T)

implement Product<Cell<Int32>, Cell<Int64>> (.Result: Type = Int32, .multiply = _multiply)

_multiply := (.left: &Cell<Int32>, .right: &Cell<Int64>) -> (.value: Int32) {
    value = left&.value
}

main := () -> () {
    left ::= Cell<Int32>(42)
    right ::= Cell<Int64>(7)
    if multiply(&left, &right).value != 42 { abort }
}

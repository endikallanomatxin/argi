Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row := (.value: Int32)

Column := (.value: Int32)

Kind#(.Input: Type): Contract = (
    .Result : Type
)

implement Product#(Kind#(Row).Result, Column) (.Result: Type = Int32, .multiply = _multiply)

implement Kind#(Row) (.Result: Type = Row)

_multiply := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
    value = left&.value * right&.value
}

main := () -> (.status_code: Int32 = 0) {

    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}

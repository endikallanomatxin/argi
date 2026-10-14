Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    .multiply: (.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

Kind#(.Input: Type): Contract = (
    .Result: Type
)
implement Kind#(Row) (.Result: Type = Row)
implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _multiply)
implement Product#(Kind#(Row).Result, Column) (.Result: Type = Int64, .multiply = _multiply)

_multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) := {
    value = left&.value * right&.value
}

main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}

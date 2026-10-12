Product#(.Result: Type, .Count: Int): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

satisfies Product#(Row, Column) = (.Result: Int32, .Count = 4)

multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Count) := {
    value = left&.value * right&.value
}

main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
}

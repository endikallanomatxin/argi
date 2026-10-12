Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    multiply(.left: &Left, .right: &Right) -> (.value: Result)
    .Count: Int
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Product#(.Right: Column, .Left: Row) = (.Count = 2, .Result: Int32)
multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) := {
    value = left&.value * right&.value
}
Buffer#(.n: Int): Type = (.values: Array#(.n = n, .t: Int32))
main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    if multiply(&row, &column).value != 42 { abort }
    buffer ::= Buffer#(.n = Product#(Row, Column).Count)((20, 22))
    if buffer.values[0] + buffer.values[1] != 42 { abort }
}

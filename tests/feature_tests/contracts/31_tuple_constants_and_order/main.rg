Pair#(.Left: Type, .Right: Type): Contract = (
    .Count: Int
    .Result: Type

    .pair: (.left: &Left, .right: &Right) -> (.value: Array#(.n = Count, .t: Result)) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
implement Pair#(.Right: Column, .Left: Row) (.Result: Type = Int32, .Count: Int = 2, .pair = _forward_pair)
implement Pair#(Column, Row) (.Count: Int = 1, .Result: Type = Int64, .pair = _reverse_pair)
_forward_pair(.left: &Row, .right: &Column) -> (.value: Array#(2, Int32)) := { value = (left&.value, right&.value) }
_reverse_pair(.left: &Column, .right: &Row) -> (.value: Array#(1, Int64)) := { value = (42,) }
main() -> () := {
    row ::= Row(6)
    column ::= Column(7)
    result ::= pair(&row, &column)
    reversed ::= pair(&column, &row)
    if result[0] != 6 { abort }
    if result[1] != 7 { abort }
    if reversed[0] != 42 { abort }
}

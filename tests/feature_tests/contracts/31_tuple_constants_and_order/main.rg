Pair#(.Count: Int, .Result: Type): Contract#(.Left: Type, .Right: Type) = (
    pair(.left: &Left, .right: &Right) -> (.value: Array#(.n = Count, .t: Result)) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Pair#(.Right: Column, .Left: Row) = (.Result: Int32, .Count = 2)
satisfies Pair#(Column, Row) = (.Count = 1, .Result: Int64)
pair(.left: &Row, .right: &Column) -> (.value: Array#(2, Int32)) := { value = (left&.value, right&.value) }
pair(.left: &Column, .right: &Row) -> (.value: Array#(1, Int64)) := { value = (42,) }
main() -> () := {
    row ::= Row(6)
    column ::= Column(7)
    result ::= pair(&row, &column)
    reversed ::= pair(&column, &row)
    if result[0] != 6 { abort }
    if result[1] != 7 { abort }
    if reversed[0] != 42 { abort }
}

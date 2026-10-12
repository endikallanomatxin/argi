Shape#(.Count: Int): Contract#(.Left: Type, .Right: Type) = ()
Row: Type = ()
Column: Type = ()
satisfies Shape#(Row, Column) = (.Count = 2)
satisfies Shape#(Column, Row) = (.Count = 3)
sum(.values: &Array#(.n = Shape#(Row, Column).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
sum(.values: &Array#(.n = Shape#(Column, Row).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] + values&[2] }
main() -> () := {
    two ::= (20, 22)
    three ::= (10, 12, 20)
    if sum(&two).value != 42 { abort }
    if sum(&three).value != 42 { abort }
}

Summation#(.Values: Type): Contract = (
    .sum : (.values: &Values) -> (.value: Int32)
)

Shape#(.Left: Type, .Right: Type): Contract = (
    .Count : Int
)

Row: Type = ()

Column: Type = ()

implement Shape#(Row, Column) (.Count: Int = 2)

implement Shape#(Column, Row) (.Count: Int = 3)

_sum_two := (.values: &Array#(.n = Shape#(Row, Column).Count, .t: Int32)) -> (.value: Int32) {
    value = [values&[0] + values&[1]]
}

_sum_three := (.values: &Array#(.n = Shape#(Column, Row).Count, .t: Int32)) -> (.value: Int32) {
    value = [values&[0] + values&[1] + values&[2]]
}

implement Summation#(Array#(.n = Shape#(Row, Column).Count, .t: Int32)) (.sum = _sum_two)

implement Summation#(Array#(.n = Shape#(Column, Row).Count, .t: Int32)) (.sum = _sum_three)

main := () -> () {
    two ::= (20, 22)
    three ::= (10, 12, 20)
    if sum(&two).value != 42 { abort }
    if sum(&three).value != 42 { abort }
}

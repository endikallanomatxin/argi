Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .Scale: Int
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)

OtherProduct#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .multiply: (.left: &Left, .right: &Right) -> (.result: Result)
)

implement Product#(Row, Column) (
    .multiply =
        (.left: &Row, .right: &Column) -> (.result: Result) {
        result = left&.value * right&.value * Scale
    }
    .Scale: Int = 2
    .Result: Type = Int32
)

implement OtherProduct#(Row, Column) (
    .Result: Type = Int32
    .multiply = (.left: &Row, .right: &Column) -> (.result: Result) {
        result = left&.value + right&.value
    }
)

product#(.A: Type, .B: Type) := (.left: &A, .right: &B) -> (.result: Product#(A, B).Result) {
    result = Product#(A, B).multiply(left, right).result
}

main := () -> (.status_code: Int32 = 0) {
    row ::= Row(6)
    column ::= Column(7)
    if Product#(Row, Column).multiply(&row, &column).result != 84 { abort }
    if product#(Row, Column)(&row, &column).result != 84 { abort }
    if OtherProduct#(Row, Column).multiply(&row, &column).result != 13 { abort }
}

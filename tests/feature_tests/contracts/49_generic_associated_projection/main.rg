Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)

Row: Type = (.value: Int32)
Column: Type = (.value: Int32)

satisfies Product#(Row, Column) = (.Result: Int32)

multiply(.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) := {
    value = left&.value * right&.value
}

product#(.A: Type, .B: Type)(.left: &A, .right: &B) -> (.value: Product#(A, B).Result) := {
    value = multiply(left, right).value
}

main() -> (.status_code: Int32 = 0) := {
    row ::= Row(6)
    column ::= Column(7)
    if product(&row, &column).value != 42 { abort }
}

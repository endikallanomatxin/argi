Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 9223372036854775807)
sum(.values: &Array#(.n = Shape#(Cell).Count + 1, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
main() -> () := {
    values ::= (20, 22)
    if sum(&values).value != 42 { abort }
}

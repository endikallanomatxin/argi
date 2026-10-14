Shape#(.Input: Type): Contract = (
    .Count: Type
)
Cell: Type = ()
implement Shape#(Cell) (.Count: Type = Int32)
sum(.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
main() -> () := {
    values ::= (20, 22)
    if sum(&values).value != 42 { abort }
}

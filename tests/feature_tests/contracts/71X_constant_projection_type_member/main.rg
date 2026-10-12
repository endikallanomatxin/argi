Shape#(.Count: Type): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count: Int32)
sum(.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
main() -> () := {
    values ::= (20, 22)
    if sum(&values).value != 42 { abort }
}

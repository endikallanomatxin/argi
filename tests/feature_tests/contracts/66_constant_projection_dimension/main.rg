Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
sum(.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
main() -> () := {
    values ::= (20, 22)
    if sum(&values).value != 42 { abort }
}

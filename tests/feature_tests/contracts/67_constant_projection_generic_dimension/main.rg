Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
Box#(.T: Type): Type = (.values: Array#(.n = Shape#(T).Count, .t: Int32))
sum#(.T: Type)(.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
main() -> () := {
    box ::= Box#(Cell)((20, 22))
    if sum(Cell(), &box.values).value != 42 { abort }
}

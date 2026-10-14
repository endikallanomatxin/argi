Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
implement Shape#(Cell) (.Count: Int = 2)
first#(.T: Type, .n: Int)(.values: &Array#(.n = n, .t: T)) -> (.value: T) := { value = values&[0] }
main() -> () := {
    values ::= (42, 0)
    if first#(.n = Shape#(Cell).Count, .T: Int32)(&values).value != 42 { abort }
}

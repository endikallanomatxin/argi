Shape#(.Input: Type): Contract = (
    .Element: Type
)
Cell: Type = ()
satisfies Shape#(Cell) = (.Element: Int32)
first#(.n: Int)(.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) := { value = values&[0] }
main() -> () := {
    values ::= (42, 0)
    first#(.n = Shape#(Cell).Element)(&values)
}

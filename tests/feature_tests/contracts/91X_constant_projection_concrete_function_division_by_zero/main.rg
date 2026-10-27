Shape#(.Input: Type): Contract = (
    .Count : Int
)

Cell: Type = ()

implement Shape#(Cell) (.Count: Int = 2)

sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
    value = [values&[0] + values&[1]]
}

take := #(.n: Int) (.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) {
    value = [values&[0] + values&[1]]
}

forward := #(.T: Type) (.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (
    .value : Int32
) { value = take#(.n = Shape#(T).Count)(values).value }

main := () -> () {
    values ::= (20, 22)
    if take#(.n = Shape#(Cell).Count / 0)(&values).value != 42 { abort }
}

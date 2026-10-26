Shape<.Input: Type>: Contract = (
    .Count : Int
)

Cell: Type = ()

implement Shape<Cell> (.Count: Int = 2)

sum := (.values: &Array<.n = Shape<Cell>.Count + 1, .t: Int32>) -> (.value: Int32) {
    value = [values&[0] + values&[1] + values&[2]]
}

main := () -> () {
    values ::= (10, 12, 20)
    if sum(&values).value != 42 { abort }
}

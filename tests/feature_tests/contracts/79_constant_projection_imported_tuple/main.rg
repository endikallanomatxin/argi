dep := import ("./dep")

sum := (.values: &Array<.n = dep.Shape<dep.Cell>.Count, .t: Int32>) -> (.value: Int32) {
    value = [values&[0] + values&[1]]
}

main := () -> () {
    values ::= (20, 22)
    if sum(&values).value != 42 { abort }
}

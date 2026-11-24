Cell := (.value: Int32)

main := () -> () {
    cell ::= Cell(0)
    shared ::= $$&cell
}

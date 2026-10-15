Source#(.Provider: Type): Contract = (.Item: Type)
Cell: Type = ()
implement Source#(Cell) (.Item: Type = Int32)

consume#(.T: Type: Source#(.Provider: T, .Item: UInt8)) := (.source: &T) -> () {}
main := () -> () {
    cell ::= Cell()
    consume(&cell)
}

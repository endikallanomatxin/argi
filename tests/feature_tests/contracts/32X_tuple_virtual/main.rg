Pair#(.Left: Type, .Right: Type): Contract = ()
Cell: Type = ()
satisfies Pair#(Cell, Cell)
main() -> () := {
    cell ::= Cell()
    handle ::= to_virtual#(.contract: Pair)(&cell)
}

Pair: Contract#(.Left: Type, .Right: Type) = ()
Cell: Type = ()
satisfies Pair#(Cell, Cell)
main() -> () := {
    cell ::= Cell()
    handle ::= to_virtual#(.contract: Pair)(&cell)
}

Pair<.Left: Type, .Right: Type>: Contract = ()

Cell: Type = ()

implement Pair<Cell, Cell> ()

main := () -> () {
    cell ::= Cell()
    handle ::= to_virtual<.contract: Pair>(&cell)
}

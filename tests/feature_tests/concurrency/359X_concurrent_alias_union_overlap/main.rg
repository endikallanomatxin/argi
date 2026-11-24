Cell: CStruct = (.value: Int32)
Overlay: CUnion = (.left: Cell, .right: Cell)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    overlay :: Overlay = (.left = (.value = 1))
    shared ::= $$&overlay.left
    if overlay.right.value == 0 { abort }
}

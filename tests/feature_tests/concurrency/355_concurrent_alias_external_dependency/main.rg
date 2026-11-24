Cell := (.external: $&Int32)
implement ConcurrentAlias#(Cell) ()

main := () -> () {
    external ::= 1
    alias ::= $&external
    cell ::= Cell(alias)
    shared ::= $$&cell
    alias& = 7
    recover_ordinary(.owner = $&cell)
    if cell.external& != 7 { abort }
}

Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
implement Shape#(Cell) (.Count: Int = 2)
read(.values: &Array#(.n = Shape#(Cell).Missing, .t: Int32)) -> () := {}
main() -> () := {}

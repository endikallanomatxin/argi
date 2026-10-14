Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()

implement Shape#(Cell) (.Count: Int = 2)

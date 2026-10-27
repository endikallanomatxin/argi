Shape#(.Input: Type): Contract = (
    .Count : Int
)

Cell: Type = ()

implement Shape#(Cell) (.Count: Int = -1)

invalid := #(.T: Type) (.tag: T) -> (.value: Array#(.n = Shape#(T).Count, .t: Int32)) {}

main := () -> () { invalid#(.T: Cell) (Cell()) }

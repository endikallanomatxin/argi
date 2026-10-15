Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
first#(.n: Int)(.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) := { value = values&[0] }

implement Shape#(Cell) (.Count: Int = 2)

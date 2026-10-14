Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
implement Shape#(Cell) (.Count: Int = 9223372036854775807)
invalid#(.T: Type)(.tag: T) -> (.value: Array#(.n = Shape#(T).Count + 1, .t: Int32)) := {}
main() -> () := { invalid#(.T: Cell)(Cell()) }

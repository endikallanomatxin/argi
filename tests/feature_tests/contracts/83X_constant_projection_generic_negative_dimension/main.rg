Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = -1)
invalid#(.T: Type)(.tag: T) -> (.value: Array#(.n = Shape#(T).Count, .t: Int32)) := {}
main() -> () := { invalid#(.T: Cell)(Cell()) }

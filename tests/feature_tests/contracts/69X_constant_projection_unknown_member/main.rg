Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
read(.values: &Array#(.n = Shape#(Cell).Missing, .t: Int32)) -> () := {}
main() -> () := {}

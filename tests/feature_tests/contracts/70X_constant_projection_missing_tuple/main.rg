Shape#(.Count: Int): Contract#(.Input: Type) = ()
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
read(.values: &Array#(.n = Shape#(Int32).Count, .t: Int32)) -> () := {}
main() -> () := {}

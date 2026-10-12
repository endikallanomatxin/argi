Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
read(.values: &Array#(.n = Shape#(Cell).Missing, .t: Int32)) -> () := {}
main() -> () := {}

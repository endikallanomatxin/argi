Shape#(.Input: Type): Contract = (
    .Count: Int
)
Cell: Type = ()
satisfies Shape#(Cell) = (.Count = 2)
read(.values: &Array#(.n = Shape#(Int32).Count, .t: Int32)) -> () := {}
main() -> () := {}

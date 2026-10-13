Point: Type = (._x: Int32)
implement Init#(Point) (
    .Args: Type = (.x: Int32)
    .Result: Type = Int32
    .init = (.args: Args) -> (.result: Result) { result = args.x }
)
main := () -> () { Point(.x = 10) }

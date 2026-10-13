Point: Type = (.value: Int32)
implement Init#(Point) (
    .Args: Type = Int32
    .Result: Type = Point
    .init = (.args: Args) -> (.result: Result) { result = (.value = args) }
)
main := () -> () {}

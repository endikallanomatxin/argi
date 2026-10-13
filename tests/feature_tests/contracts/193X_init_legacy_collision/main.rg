Point: Type = (.value: Int32)
Point init(.value: Int32) -> (.result: Point) := { result = (.value = value) }
implement Init#(Point) (
    .Args: Type = (.value: Int32)
    .Result: Type = Point
    .init = (.args: Args) -> (.result: Result) { result = (.value = args.value) }
)
main := () -> () { Point(.value = 42) }

Point: Type = (.value: Int32)
implement Init#(Point, Int32) (
    .Result: Type = Point
    .init = (.args: Int32) -> (.result: Result) { result = (.value = args) }
)
main := () -> () {}

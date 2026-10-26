Point := (.value: Int32)
Point init(.value: Int32) -> (.result: Point) := { result = (.value = value) }
implement Init < Point, (.value: Int32) > (
    .Result : Type = Point
    .init   = (.args: (.value: Int32)) -> (.result: Result) { result = (.value = args.value) }
)
main := () -> () { Point(.value = 42) }

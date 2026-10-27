Point := (.value: Int32)

PointInitArgs: Type = Int32

implement Init#(Point, PointInitArgs) (
    .Result : Type = Point

    .init = PointInitArgs -> (.result: Result) { result = (.value = 0) }
)

main := () -> () { Point() }

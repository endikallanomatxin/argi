Point := (._x: Int32)

PointInitArgs: Type = (.x: Int32)

implement Init#(Point, PointInitArgs) (
    .Result : Type = Int32

    .init = PointInitArgs -> (.result: Result) { result = x }
)

main := () -> () { Point(.x = 10) }

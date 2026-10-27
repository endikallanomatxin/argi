Point := (._x: Int32)

implement Init#(Point) (
    .init = (.x: Int32) -> (.result: Int32) { result = x }
)

main := () -> () { Point(.x = 10) }

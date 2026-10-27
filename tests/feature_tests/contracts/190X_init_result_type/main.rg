Point := (._x: Int32)

implement Init#(Point, (.x: Int32)) (
    .Result : Type = Int32
    .init   = (.args: (.x: Int32)) -> (.result: Result) { result = args.x }
)

main := () -> () { Point(.x = 10) }

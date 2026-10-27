Point := (.value: Int32)

implement Init#(Point) (
    .init = Int32 -> (.result: Point) { result = (.value = 0) }
)

main := () -> () { Point() }

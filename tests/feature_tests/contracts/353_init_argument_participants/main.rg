SharedArgs := (.value: Int32)

First := (.value: Int32)

Second := (.value: Int32)

implement Init#(First, SharedArgs) (
    .Result : Type = First
    .init   = SharedArgs -> (.result: Result) { result = (.value = value) }
)

implement Init#(Second, SharedArgs) (
    .Result : Type = Second
    .init   = SharedArgs -> (.result: Result) { result = (.value = value) }
)

Angle := (.value: Int32)

DegreesArgs := (.value: Int32)

RadiansArgs := (.value: Int32)

implement Init#(Angle, DegreesArgs) (
    .Result : Type = Angle
    .init   = DegreesArgs -> (.result: Result) { result = (.value = value) }
)

implement Init#(Angle, RadiansArgs) (
    .Result : Type = Angle
    .init   = RadiansArgs -> (.result: Result) { result = (.value = value + 1) }
)

main := () -> (.status_code: Int32 = 0) {
    if First(3).value != 3 or Second(7).value != 7 { status_code = 1 }
    degrees ::= Init#(Angle, DegreesArgs).init(10)
    radians ::= Init#(Angle, RadiansArgs).init(10)
    if degrees.value != 10 or radians.value != 11 { status_code = 2 }
    known ::= #run () -> (.result: Int32) { result = First(9).value }
    if known != 9 { status_code = 3 }
}

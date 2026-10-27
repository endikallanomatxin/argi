Angle := (.value: Int32)

DegreesArgs := (.value: Int32)

RadiansArgs := (.value: Int32)

implement Init#(Angle, DegreesArgs) (
    .Result : Type = Angle
    .init   = DegreesArgs -> (.result: Result) { result = (.value = value) }
)

implement Init#(Angle, RadiansArgs) (
    .Result : Type = Angle
    .init   = RadiansArgs -> (.result: Result) { result = (.value = value) }
)

main := () -> () { value ::= Angle(.value = 10) }

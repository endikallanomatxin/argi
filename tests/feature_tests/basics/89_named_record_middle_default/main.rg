Point := #(.Scalar: Type) (.x: Scalar, .y: Scalar)

Span := #(.Scalar: Type) (
    .start  : Point#(Scalar),
    .end    : Point#(Scalar),
    .center : Point#(Scalar)  = (.x = 0.0, .y = 0.0),
    .sweep  : Scalar         = 0.0
)

make := #(.Scalar: Type) (.radius: Scalar) -> (.span: Span#(Scalar)) {
    span = (.start = (.x = radius, .y = 0.0), .end = (.x = radius, .y = 0.0), .sweep = 6.0)
}

main := () -> (.status_code: Int32 = 0) {
    radius: Float64 = 2.0
    value ::= make(.radius = radius).span
    if value.center.x != 0.0 or value.center.y != 0.0 or value.sweep != 6.0 { status_code = 1 }
    second: Span#(Float64) = (
        .sweep = 3.0
        .end   = (.x = 0.0, .y = 1.0)
        .start = (.x = 1.0, .y = 0.0)
    )
    if second.center.x != 0.0 or second.sweep != 3.0 or second.end.y != 1.0 { status_code = 2 }
    third :: Span#(Float64) = (.start = (.x = 0.0, .y = 0.0), .end = (.x = 1.0, .y = 0.0))
    third = (.sweep = 4.0, .start = (.x = 2.0, .y = 0.0), .end = (.x = 3.0, .y = 0.0))
    if third.sweep != 4.0 or third.center.y != 0.0 or third.start.x != 2.0 { status_code = 3 }
}

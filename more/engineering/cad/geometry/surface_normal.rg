-- Unit normal of the support, aligned with du cross dv at regular chart points.
-- Defined at sphere poles by analytic continuation, independently of longitude.
-- No face trim or topological orientation is involved in this query.
surface_normal := #(.Scalar: Type: Float) (.surface: Surface#(Scalar), .u: Scalar, .v: Scalar) -> (
    .result : Errable#(Displacement#(Scalar), GeometryErrors)
) {
    validate_surface(surface)!
    singular ::= validate_surface_parameters(.surface = surface, .u = u, .v = v)!
    match surface {
        ..plane p {
            basis ::= frame(.origin = p.value.origin, .axis = p.value.normal)!
            result = ..ok basis.z
        }
        ..cylinder c {
            result = ..ok _frame_vector(
                .frame = c.frame, .x = cos(u).result, .y = sin(u).result, .z = 0.0
            ).value
        }
        ..sphere s {
            if singular {
                sign :: Scalar = 1.0
                if v < 0.0 { sign = -1.0 }
                result = ..ok _frame_vector(
                    .frame = s.frame, .x = 0.0, .y = 0.0, .z = sign
                ).value
                return
            }
            radial ::= cos(v).result
            result = ..ok _frame_vector(
                .frame = s.frame
                .x     = radial * cos(u).result
                .y     = radial * sin(u).result
                .z     = sin(v).result
            ).value
        }
        ..torus t {
            radial ::= cos(v).result
            result = ..ok _frame_vector(
                .frame = t.frame
                .x     = radial * cos(u).result
                .y     = radial * sin(u).result
                .z     = sin(v).result
            ).value
        }
    }
}

-- Transform a local vector without translating it. Validated
-- right-handed orthonormal frames preserve vector length and orientation to precision.
_frame_vector := #(.Scalar: Type: Float) (
    .frame: Frame#(Scalar), .x: Scalar, .y: Scalar, .z: Scalar
) -> (.value: Displacement#(Scalar)) {
    value = (
        .x = frame.x.x * x + frame.y.x * y + frame.z.x * z
        .y = frame.x.y * x + frame.y.y * y + frame.z.y * z
        .z = frame.x.z * x + frame.y.z * y + frame.z.z * z
    )
}

-- Partial derivatives in the support's existing chart, not unit tangents.
-- The chart can be singular even when the support and its normal are regular.
SurfaceDerivatives := #(.Scalar: Type: Float) (
    .du       : Displacement#(Scalar),
    .dv       : Displacement#(Scalar),
    .singular : Bool
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(SurfaceDerivatives#(Scalar)) ()

surface_derivatives := #(.Scalar: Type: Float) (
    .surface: Surface#(Scalar), .u: Scalar, .v: Scalar
) -> (.result: Errable#(SurfaceDerivatives#(Scalar), GeometryErrors)) {
    validate_surface(surface)!
    singular ::= validate_surface_parameters(.surface = surface, .u = u, .v = v)!
    zero: Displacement#(Scalar) = (0.0, 0.0, 0.0)
    du ::= zero
    dv ::= zero
    match surface {
        ..plane p {
            basis ::= frame(.origin = p.value.origin, .axis = p.value.normal)!
            du = basis.x
            dv = basis.y
        }
        ..cylinder c {
            du = _frame_vector(
                .frame = c.frame
                .x     = 0.0 - c.radius * sin(u).result
                .y     = [c.radius * cos(u).result]
                .z     = 0.0
            ).value
            dv = c.frame.z
        }
        ..sphere s {
            radial ::= s.radius * cos(v).result
            axial ::= s.radius * sin(v).result
            if singular {
                -- Exact domain endpoints collapse longitude, despite trig
                -- rounding of cos(pi/2). Nearby regular points are not snapped.
                radial = 0.0
                axial = s.radius
                if v < 0.0 { axial = 0.0 - s.radius }
            }
            du = _frame_vector(
                .frame = s.frame
                .x     = 0.0 - radial * sin(u).result
                .y     = [radial * cos(u).result]
                .z     = 0.0
            ).value
            dv = _frame_vector(
                .frame = s.frame
                .x     = 0.0 - axial * cos(u).result
                .y     = [0.0 - axial * sin(u).result]
                .z     = radial
            ).value
        }
        ..torus t {
            radial ::= t.major_radius + t.minor_radius * cos(v).result
            axial ::= 0.0 - t.minor_radius * sin(v).result
            du = _frame_vector(
                .frame = t.frame
                .x     = 0.0 - radial * sin(u).result
                .y     = [radial * cos(u).result]
                .z     = 0.0
            ).value
            dv = _frame_vector(
                .frame = t.frame
                .x     = axial * cos(u).result
                .y     = [axial * sin(u).result]
                .z     = [t.minor_radius * cos(v).result]
            ).value
        }
    }
    if finite_displacement(du).ok == false or finite_displacement(dv).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok(.du = du, .dv = dv, .singular = singular)
}

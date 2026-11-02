-- A support chart is independent of face trims. Periodic coordinates remain
-- unwrapped: a fundamental interval is a reference, not an evaluation bound.
ParameterAxis := #(.Scalar: Type: Float) (
    ..unbounded,
    ..periodic(.origin: Scalar, .period: Scalar),
    ..bounded(
        .lower          : Scalar,
        .upper          : Scalar,
        .lower_singular : Bool,
        .upper_singular : Bool
    )
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(ParameterAxis#(Scalar)) ()

SurfaceParameterDomain := #(.Scalar: Type: Float) (
    .u : ParameterAxis#(Scalar),
    .v : ParameterAxis#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(SurfaceParameterDomain#(Scalar)) ()

-- Describes the built-in support chart, not a region or a certificate that the
-- supplied support is valid. Surface validation is a separate operation.
surface_parameter_domain := #(.Scalar: Type: Float) (.surface: Surface#(Scalar)) -> (
    .domain : SurfaceParameterDomain#(Scalar)
) {
    angle: ParameterAxis#(Scalar) = ..periodic(.origin = 0.0, .period = 6.283185307179586)
    unbounded: ParameterAxis#(Scalar) = ..unbounded
    latitude: ParameterAxis#(Scalar) = ..bounded(
        .lower          = -1.5707963267948966
        .upper          = 1.5707963267948966
        .lower_singular = true
        .upper_singular = true
    )
    domain = (.u = unbounded, .v = unbounded)
    match surface {
        ..plane _ {}
        ..cylinder _ { domain.u = angle }
        ..sphere _ {
            domain.u = angle
            domain.v = latitude
        }
        ..torus _ {
            domain.u = angle
            domain.v = angle
        }
    }
}

-- A singular boundary collapses the complementary chart direction, as sphere
-- longitude does at a pole. This reports chart regularity, not a model vertex.
-- No tolerance is used: nearby regular points must not be snapped to a pole.
validate_surface_parameters := #(.Scalar: Type: Float) (
    .surface: Surface#(Scalar), .u: Scalar, .v: Scalar
) -> (.result: Errable#(Bool, GeometryErrors)) {
    domain ::= surface_parameter_domain(surface).domain
    a ::= _parameter_axis_singularity(.axis = domain.u, .value = u)!
    b ::= _parameter_axis_singularity(.axis = domain.v, .value = v)!
    singular ::= a or b
    result = ..ok singular
}

_parameter_axis_singularity := #(.Scalar: Type: Float) (
    .axis: ParameterAxis#(Scalar), .value: Scalar
) -> (.result: Errable#(Bool, GeometryErrors)) {
    if is_finite(value).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    singular :: Bool = false
    match axis {
        ..unbounded {}
        ..periodic _ {}
        ..bounded interval {
            if value < interval.lower or value > interval.upper {
                result = ..error(.reason = ..out_of_bounds)
                return
            }
            singular = [
                value == interval.lower and interval.lower_singular
                or [value == interval.upper and interval.upper_singular]
            ]
        }
    }
    result = ..ok singular
}

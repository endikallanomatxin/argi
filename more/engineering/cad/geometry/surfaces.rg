-- Parameter charts are geometry only: their periodic cuts are never B-rep edges.
Frame := #(.Scalar: Type: Float) (
    .origin : Point#(Scalar),
    .x      : Displacement#(Scalar),
    .y      : Displacement#(Scalar),
    .z      : Displacement#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Frame#(Scalar)) ()

Circle := #(.Scalar: Type: Float) (.frame: Frame#(Scalar), .radius: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Circle#(Scalar)) ()

Surface := #(.Scalar: Type: Float) (
    ..plane(.value: Plane#(Scalar)),
    ..cylinder(.frame: Frame#(Scalar), .radius: Scalar),
    ..sphere(.frame: Frame#(Scalar), .radius: Scalar),
    ..torus(.frame: Frame#(Scalar), .major_radius: Scalar, .minor_radius: Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Surface#(Scalar)) ()

-- The derived radial axes do not create distinguished meridians in topology.
frame := #(.Scalar: Type: Float) (.origin: Point#(Scalar), .axis: Displacement#(Scalar)) -> (
    .result : Errable#(Frame#(Scalar), GeometryErrors)
) {
    if [
        finite_point#(Scalar)(origin).ok == false
        or is_finite(axis.x).ok == false
        or is_finite(axis.y).ok == false
        or is_finite(axis.z).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    length ::= norm#(Scalar)(axis).value
    if is_finite(length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if length <= 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    z: Displacement#(Scalar) = (
        .x = axis.x / length
        .y = axis.y / length
        .z = axis.z / length
    )
    helper :: Displacement#(Scalar) = (1.0, 0.0, 0.0)
    if z.x > 0.5 or z.x < -0.5 { helper = (0.0, 1.0, 0.0) }
    raw ::= cross#(Scalar)(.left = helper, .right = z).result
    scale ::= norm#(Scalar)(raw).value
    x: Displacement#(Scalar) = (raw.x / scale, raw.y / scale, raw.z / scale)
    y ::= cross#(Scalar)(.left = z, .right = x).result
    result = ..ok(.origin = origin, .x = x, .y = y, .z = z)
}

-- Frame orthogonality uses a precision guard, independent of model-unit tolerance.
validate_frame := #(.Scalar: Type: Float) (.value: Frame#(Scalar)) -> (
    .result : Errable#(Void, GeometryErrors)
) {
    if finite_point#(Scalar)(value.origin).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    guard: Scalar = _float_resolution#(Scalar)().value * 64.0
    xx ::= norm#(Scalar)(value.x).value
    yy ::= norm#(Scalar)(value.y).value
    zz ::= norm#(Scalar)(value.z).value
    handed ::= dot#(Scalar)(
        .left = cross#(Scalar)(.left = value.x, .right = value.y).result, .right = value.z
    ).value
    if [
        is_finite(xx).ok == false
        or is_finite(yy).ok == false
        or is_finite(zz).ok == false
        or is_finite(handed).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    if [
        xx < 1.0 - guard
        or xx > 1.0 + guard
        or yy < 1.0 - guard
        or yy > 1.0 + guard
        or zz < 1.0 - guard
        or zz > 1.0 + guard
        or handed < 1.0 - guard
        or handed > 1.0 + guard
    ] {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    xy ::= dot#(Scalar)(.left = value.x, .right = value.y).value
    yz ::= dot#(Scalar)(.left = value.y, .right = value.z).value
    zx ::= dot#(Scalar)(.left = value.z, .right = value.x).value
    if [
        xy < 0.0 - guard
        or xy > guard
        or yz < 0.0 - guard
        or yz > guard
        or zx < 0.0 - guard
        or zx > guard
    ] {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    result = ..ok Void()
}

_frame_point := #(.Scalar: Type: Float) (
    .frame: Frame#(Scalar), .x: Scalar, .y: Scalar, .z: Scalar
) -> (.result: Errable#(Point#(Scalar), GeometryErrors)) {
    p: Point#(Scalar) = (
        .x = frame.origin.x + frame.x.x * x + frame.y.x * y + frame.z.x * z
        .y = frame.origin.y + frame.x.y * x + frame.y.y * y + frame.z.y * z
        .z = frame.origin.z + frame.x.z * x + frame.y.z * y + frame.z.z * z
    )
    if finite_point#(Scalar)(p).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok p
}

surface_periodicity := #(.Scalar: Type: Float) (.surface: Surface#(Scalar)) -> (
    .u: Bool, .v: Bool
) {
    domain ::= surface_parameter_domain(surface).domain
    u = false
    v = false
    match domain.u { ..periodic _ { u = true } ..unbounded {} ..bounded _ {} }
    match domain.v { ..periodic _ { v = true } ..unbounded {} ..bounded _ {} }
}

-- Angles are radians. Cylinder v is axial distance; sphere v is latitude.
-- Torus v is the tube angle. Pole chart singularities are not vertices.
surface_point := #(.Scalar: Type: Float) (.surface: Surface#(Scalar), .u: Scalar, .v: Scalar) -> (
    .result : Errable#(Point#(Scalar), GeometryErrors)
) {
    validate_surface#(Scalar)(surface)!
    validate_surface_parameters(.surface = surface, .u = u, .v = v)!
    match surface {
        ..plane p {
            basis ::= frame#(Scalar)(.origin = p.value.origin, .axis = p.value.normal)!
            result = _frame_point#(Scalar)(.frame = basis, .x = u, .y = v, .z = 0.0)
        }
        ..cylinder c {
            result = _frame_point#(Scalar)(
                .frame = c.frame
                .x     = c.radius * cos(u).result
                .y     = c.radius * sin(u).result
                .z     = v
            )
        }
        ..sphere s {
            radial ::= s.radius * cos(v).result
            result = _frame_point#(Scalar)(
                .frame = s.frame
                .x     = radial * cos(u).result
                .y     = radial * sin(u).result
                .z     = s.radius * sin(v).result
            )
        }
        ..torus t {
            radial ::= t.major_radius + t.minor_radius * cos(v).result
            result = _frame_point#(Scalar)(
                .frame = t.frame
                .x     = radial * cos(u).result
                .y     = radial * sin(u).result
                .z     = t.minor_radius * sin(v).result
            )
        }
    }
}

circle_point := #(.Scalar: Type: Float) (.circle: Circle#(Scalar), .angle: Scalar) -> (
    .result : Errable#(Point#(Scalar), GeometryErrors)
) {
    validate_circle(circle)!
    if is_finite(angle).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    result = _frame_point#(Scalar)(
        .frame = circle.frame
        .x     = circle.radius * cos(angle).result
        .y     = circle.radius * sin(angle).result
        .z     = 0.0
    )
}

validate_circle := #(.Scalar: Type: Float) (.circle: Circle#(Scalar)) -> (
    .result : Errable#(Void, GeometryErrors)
) {
    validate_frame#(Scalar)(circle.frame)!
    if is_finite(circle.radius).ok == false or circle.radius <= 0.0 {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    result = ..ok Void()
}

-- Validate analytic support data before evaluating a chart. Trim bounds belong
-- to the face, not to this support-level operation.
validate_surface := #(.Scalar: Type: Float) (.surface: Surface#(Scalar)) -> (
    .result : Errable#(Void, GeometryErrors)
) {
    match surface {
        ..plane p {
            frame#(Scalar)(.origin = p.value.origin, .axis = p.value.normal)!
        }
        ..cylinder c {
            validate_frame#(Scalar)(c.frame)!
            if [is_finite(c.radius).ok == false or c.radius <= 0.0] {
                result = ..error(.reason = ..invalid_surface)
                return
            }
        }
        ..sphere s {
            validate_frame#(Scalar)(s.frame)!
            if is_finite(s.radius).ok == false or s.radius <= 0.0 {
                result = ..error(.reason = ..invalid_surface)
                return
            }
        }
        ..torus t {
            validate_frame#(Scalar)(t.frame)!
            if [
                is_finite(t.major_radius).ok == false
                or is_finite(t.minor_radius).ok == false
                or t.minor_radius <= 0.0
                or t.major_radius <= t.minor_radius
            ] {
                result = ..error(.reason = ..invalid_surface)
                return
            }
        }
    }
    result = ..ok Void()
}

-- Typed pool payloads, separate from the value-style Surface query result.
Cylinder := #(.Scalar: Type: Float) (
    .frame  : Frame#(Scalar),
    .radius : Scalar
)

Sphere := #(.Scalar: Type: Float) (.frame: Frame#(Scalar), .radius: Scalar)

Torus := #(.Scalar: Type: Float) (
    .frame        : Frame#(Scalar),
    .major_radius : Scalar,
    .minor_radius : Scalar
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Cylinder#(Scalar)) ()

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Sphere#(Scalar)) ()

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Torus#(Scalar)) ()

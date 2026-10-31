-- Derivative with respect to the support's normalized parameter, not radians
-- or arc length. Circle/ellipse supports make one full turn from zero to one.
curve_derivative := #(.Scalar: Type: Float) (.curve: Curve#(Scalar), .parameter: Scalar) -> (
    .result : Errable#(g.Displacement#(Scalar), g.GeometryErrors)
) {
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = _curve_derivative_at(.curve = curve, .parameter = parameter)
}

-- Periodic supports also accept unwrapped parameters from edge intervals.
_curve_derivative_at := #(.Scalar: Type: Float) (.curve: Curve#(Scalar), .parameter: Scalar) -> (
    .result : Errable#(g.Displacement#(Scalar), g.GeometryErrors)
) {
    derivative :: g.Displacement#(Scalar) = (0.0, 0.0, 0.0)
    scale :: Scalar = 1.0
    match curve {
        ..segment s {
            if [g.finite_point(s.start).ok == false or g.finite_point(s.end).ok == false] {
                result = ..error(.reason = ..invalid_coordinate)
                return
            }
            derivative = g.between(.from = s.start, .to = s.end).result
        }
        ..circle c {
            angle ::= parameter * 6.283185307179586
            if is_finite(angle).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            derivative = g.circle_derivative(.circle = c.value, .angle = angle)!
            scale = 6.283185307179586
        }
        ..ellipse e {
            angle ::= parameter * 6.283185307179586
            if is_finite(angle).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            derivative = g.ellipse_derivative(.ellipse = e.value, .angle = angle)!
            scale = 6.283185307179586
        }
    }
    derivative.x = derivative.x * scale
    derivative.y = derivative.y * scale
    derivative.z = derivative.z * scale
    if g.finite_displacement(derivative).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok derivative
}

-- The derivative follows the directed use's local parameter t in [0,1].
-- It includes both the edge interval width and the use's reversal sign.
halfedge_derivative := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .halfedge: HalfEdgeId, .parameter: Scalar
) -> (.result: Errable#(g.Displacement#(Scalar), g.GeometryErrors)) {
    item ::= halfedge_info(model, .halfedge = halfedge)!
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    interval ::= edge_interval(model, .edge = item.edge)!
    t ::= parameter
    scale ::= interval.end - interval.start
    if item.reversed {
        t = 1.0 - parameter;
        scale = 0.0 - scale
    }
    value ::= [1.0 - t] * interval.start + t * interval.end
    curve ::= edge_curve(model, .edge = item.edge)!
    derivative ::= _curve_derivative_at(.curve = curve, .parameter = value)!
    derivative.x = derivative.x * scale
    derivative.y = derivative.y * scale
    derivative.z = derivative.z * scale
    if g.finite_displacement(derivative).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok derivative
}

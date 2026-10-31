-- A chart derivative, distinct from a chart position. Components are changes
-- in surface u/v per unit of the p-curve's normalized parameter, not a unit vector.
ParameterDerivative := #(.Scalar: Type: Float) (.u: Scalar, .v: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(ParameterDerivative#(Scalar)) ()

pcurve_derivative := #(.Scalar: Type: Float) (.curve: PCurve#(Scalar), .parameter: Scalar) -> (
    .result : Errable#(ParameterDerivative#(Scalar), BrepErrors)
) {
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    validate_pcurve(curve)!
    derivative :: ParameterDerivative#(Scalar) = (.u = 0.0, .v = 0.0)
    match curve {
        ..line line {
            derivative = (.u = line.end.u - line.start.u, .v = line.end.v - line.start.v)
        }
        ..ellipse ellipse {
            angle ::= [1.0 - parameter] * ellipse.start + parameter * ellipse.end
            scale ::= ellipse.end - ellipse.start
            c ::= cos(angle).result
            s ::= sin(angle).result
            derivative = (
                .u = [ellipse.sine.u * c - ellipse.cosine.u * s] * scale
                .v = [ellipse.sine.v * c - ellipse.cosine.v * s] * scale
            )
        }
        ..harmonic h {
            angle ::= [1.0 - parameter] * h.start + parameter * h.end
            scale ::= h.end - h.start
            c ::= cos(angle).result
            s ::= sin(angle).result
            derivative = (
                .u = [h.linear.u - h.cosine.u * s + h.sine.u * c] * scale
                .v = [h.linear.v - h.cosine.v * s + h.sine.v * c] * scale
            )
        }
    }
    if is_finite(derivative.u).ok == false or is_finite(derivative.v).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok derivative
}

-- P-curves already include the edge interval mapping. Apply only the use's
-- reversal here; multiplying by edge interval width again would be incorrect.
halfedge_parameter_derivative := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .halfedge: HalfEdgeId, .parameter: Scalar
) -> (.result: Errable#(ParameterDerivative#(Scalar), BrepErrors)) {
    item ::= halfedge_info(model, .halfedge = halfedge)!
    match item.pcurve {
        ..none { result = ..error(.reason = ..unsupported_boundary) }
        ..some id {
            index ::= id.value | convert#(.to: UIntNative)(_)
            curve ::= get(&model&._geometry.pcurves, .index = index)!
            t ::= parameter
            if item.reversed { t = 1.0 - parameter }
            derivative ::= pcurve_derivative(.curve = curve, .parameter = t)!
            if item.reversed {
                derivative.u = 0.0 - derivative.u
                derivative.v = 0.0 - derivative.v
            }
            result = ..ok derivative
        }
    }
}

-- Evaluation accepts stationary curves; topology admission decides whether a
-- particular boundary is admissible. All coefficients must still be finite.
validate_pcurve := #(.Scalar: Type: Float) (.curve: PCurve#(Scalar)) -> (
    .result : Errable#(Void, BrepErrors)
) {
    finite ::= false
    match curve {
        ..line line {
            finite = [
                _finite_parameter_point(line.start).ok
                and _finite_parameter_point(line.end).ok
            ]
        }
        ..ellipse ellipse {
            finite = [
                _finite_parameter_point(ellipse.center).ok
                and _finite_parameter_point(ellipse.cosine).ok
                and _finite_parameter_point(ellipse.sine).ok
                and is_finite(ellipse.start).ok
                and is_finite(ellipse.end).ok
            ]
        }
        ..harmonic h {
            finite = [
                _finite_parameter_point(h.origin).ok
                and _finite_parameter_point(h.linear).ok
                and _finite_parameter_point(h.cosine).ok
                and _finite_parameter_point(h.sine).ok
                and is_finite(h.start).ok
                and is_finite(h.end).ok
            ]
        }
    }
    if finite == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    result = ..ok Void()
}

_finite_parameter_point := #(.Scalar: Type: Float) (.value: ParameterPoint#(Scalar)) -> (
    .ok : Bool
) {
    ok = is_finite(value.u).ok and is_finite(value.v).ok
}

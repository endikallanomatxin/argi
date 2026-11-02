-- Membership in admitted analytic regions. Boundary points belong to the
-- face, including the boundary of a hole. This is a chart query, not a general
-- intersection classifier or an approximate spatial inside/outside predicate.
face_contains_parameters := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .face: FaceId, .u: Scalar, .v: Scalar
) -> (.result: Errable#(Bool, BrepErrors)) {
    if is_finite(u).ok == false or is_finite(v).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    info ::= face_info(model, .face = face)!
    if info.loop_count == 0 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    support ::= face_surface(model, .face = face)!
    g.validate_surface_parameters(.surface = support, .u = u, .v = v)!
    match support {
        ..sphere _ {
            if info.loop_count != 1 {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
            loop ::= loop_info(model, .loop = info.first_loop)!
            use ::= halfedge_info(model, .halfedge = loop.first)!
            match _loop_pcurve(.model = model, .loop = info.first_loop)! {
                ..harmonic _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..line line {
                    -- Both senses change under orientation reversal; their
                    -- relation encodes the same geometric region.
                    north ::= use.reversed == info.reversed
                    inside ::= v >= line.start.v
                    if north == false { inside = [v <= line.start.v] }
                    result = ..ok inside
                }
                ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
            }
        }
        ..plane _ {
            if _face_has_circular_spans(.model = model, .face = face)! {
                result = _locate_planar_contour_face(
                    .model = model, .face = face, .u = u, .v = v
                )
                return
            }
            first ::= info.first_loop | convert#(.to: UIntNative)(_)
            i :: UIntNative = 0
            while i < info.loop_count {
                loop ::= [first + i] | convert#(.to: LoopId)(_)
                curve ::= _loop_pcurve(.model = model, .loop = loop)!
                radius ::= _ellipse_parameter_radius(.curve = curve, .u = u, .v = v)!
                if [i == 0 and radius > 1.0] or [i > 0 and radius < 1.0] {
                    result = ..ok false
                    return
                }
                i = i + 1
            }
            result = ..ok true
        }
        ..cylinder _ {
            if info.loop_count != 2 {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
            first ::= info.first_loop | convert#(.to: UIntNative)(_)
            next ::= [first + 1] | convert#(.to: LoopId)(_)
            lower ::= _cylinder_height(
                .curve = _loop_pcurve(.model = model, .loop = info.first_loop)!, .u = u
            )!
            upper ::= _cylinder_height(
                .curve = _loop_pcurve(.model = model, .loop = next)!, .u = u
            )!
            inside ::= v >= lower and v <= upper
            result = ..ok inside
        }
        ..torus _ {
            if info.loop_count != 2 {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
            first ::= info.first_loop | convert#(.to: UIntNative)(_)
            next ::= [first + 1] | convert#(.to: LoopId)(_)
            lower ::= _torus_latitude(
                .curve = _loop_pcurve(.model = model, .loop = info.first_loop)!
            )!
            upper ::= _torus_latitude(.curve = _loop_pcurve(.model = model, .loop = next)!)!
            result = _periodic_band_contains(.value = v, .lower = lower, .upper = upper)
        }
    }
}

_loop_pcurve := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .loop: LoopId) -> (
    .result : Errable#(PCurve#(Scalar), BrepErrors)
) {
    info ::= loop_info(model, .loop = loop)!
    use ::= halfedge_info(model, .halfedge = info.first)!
    match use.pcurve {
        ..none { result = ..error(.reason = ..unsupported_boundary) }
        ..some id {
            index ::= id.value | convert#(.to: UIntNative)(_)
            curve ::= get(&model&._geometry.pcurves, .index = index)!
            result = ..ok curve
        }
    }
}

_ellipse_parameter_radius := #(.Scalar: Type: Float) (
    .curve: PCurve#(Scalar), .u: Scalar, .v: Scalar
) -> (.result: Errable#(Scalar, BrepErrors)) {
    match curve {
        ..harmonic _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..line _ { result = ..error(.reason = ..unsupported_boundary) }
        ..ellipse ellipse {
            du ::= u - ellipse.center.u
            dv ::= v - ellipse.center.v
            determinant ::= [
                ellipse.cosine.u * ellipse.sine.v
                - ellipse.cosine.v * ellipse.sine.u
            ]
            x ::= [du * ellipse.sine.v - dv * ellipse.sine.u] / determinant
            y ::= [ellipse.cosine.u * dv - ellipse.cosine.v * du] / determinant
            radius ::= hypot(.left = x, .right = y).result
            if is_finite(radius).ok == false {
                result = ..error(.reason = ..numeric_range)
                return
            }
            result = ..ok radius
        }
    }
}

-- Chart conversion is separate from curve/surface compatibility. Published
-- topology retains the original supports and p-curves, never these temporaries.
_planar_contour_span := #(.Scalar: Type: Float) (.pcurve: PCurve#(Scalar), .reversed: Bool) -> (
    .result : Errable#(g.ContourSpan#(Scalar), BrepErrors)
) {
    a ::= pcurve_point(.curve = pcurve, .parameter = 0.0)!
    b ::= pcurve_point(.curve = pcurve, .parameter = 1.0)!
    span: g.ContourSpan#(Scalar) = (
        .start = (a.u, a.v)
        .end   = (b.u, b.v)
    )
    match pcurve {
        ..line _ {}
        ..harmonic _ {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..ellipse uv {
            determinant ::= uv.cosine.u * uv.sine.v - uv.cosine.v * uv.sine.u
            span.center = (uv.center.u, uv.center.v)
            span.sweep = uv.end - uv.start
            if determinant < 0.0 { span.sweep = 0.0 - span.sweep }
        }
    }
    if reversed {
        first ::= span.start
        span.start = span.end
        span.end = first
        span.sweep = 0.0 - span.sweep
    }
    result = ..ok span
}

_admit_planar_contour_region := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .plane     : g.Plane#(Scalar),
    .uses      : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .lengths   : ArrayView#(UIntNative),
    .reversed  : Bool,
    .tolerance : Scalar,
    .allocator : Virtual#(Allocator)
) -> (.result: Errable#(Void, BrepErrors)) {
    count ::= length(uses).count
    spans ::= DynamicArray#(g.ContourSpan#(Scalar))(.capacity = count, .allocator = allocator)!
    i :: UIntNative = 0
    while i < count {
        use ::= get(uses, .index = i)!
        curve ::= _pool_curve(pools, .curve = use.curve)!
        _certify_planar_trim(
            .plane     = plane
            .curve     = curve
            .interval  = use.interval
            .pcurve    = use.pcurve
            .tolerance = tolerance
        )!
        span ::= _planar_contour_span(.pcurve = use.pcurve, .reversed = use.reversed)!
        push_assume_capacity($&spans, .value = span)
        i = i + 1
    }
    g.validate_contour_region(
        .spans = view(&spans), .lengths = lengths, .tolerance = tolerance, .reversed = reversed
    )!
    result = ..ok Void()
}

-- This path supports line and circular-arc trims, including arc-only loops.
-- Genuine ellipses retain their separate analytic certificate and query.
_face_has_circular_spans := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(Bool, BrepErrors)
) {
    for loop in face_loops(model, .face = face)! {
        for use in loop_halfedges(model, .loop = loop.id)! {
            edge ::= edge_info(model, .edge = use.halfedge.edge)!
            match edge.curve {
                ..none {
                    result = ..ok false
                    return
                }
                ..some id {
                    match _pool_curve(&model&._geometry, .curve = id.value)! {
                        ..segment _ {}
                        ..circle _ {}
                        ..ellipse _ {
                            result = ..ok false
                            return
                        }
                    }
                }
            }
        }
    }
    result = ..ok true
}

_locate_planar_contour_face := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .face: FaceId, .u: Scalar, .v: Scalar
) -> (.result: Errable#(Bool, BrepErrors)) {
    exterior ::= true
    admitted ::= true
    for loop in face_loops(model, .face = face)! {
        inside ::= false
        for use in loop_halfedges(model, .loop = loop.id)! {
            match use.halfedge.pcurve {
                ..none {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..some id {
                    index ::= id.value | convert#(.to: UIntNative)(_)
                    span ::= _planar_contour_span(
                        .pcurve   = get(&model&._geometry.pcurves, .index = index)!
                        .reversed = use.halfedge.reversed
                    )!
                    spans :: [1]g.ContourSpan#(Scalar) = (span,)
                    point: g.ContourPoint#(Scalar) = (u, v)
                    location ::= g.locate_in_contour_spans(
                        .spans     = view(&spans)
                        .point     = point
                        .tolerance = model&._validation_tolerance
                    )!
                    match location {
                        ..boundary {
                            result = ..ok true
                            return
                        }
                        ..inside { inside = inside == false }
                        ..outside {}
                    }
                }
            }
        }
        if inside != exterior { admitted = false }
        exterior = false
    }
    result = ..ok admitted
}

BrepErrors := choice_union#(
    .a : BuildErrors,
    .b : (..invalid_parameter, ..unsupported_boundary, ..unsupported_parameterization)
)

CurveIntervalId := (.value: UIntNative)

PCurveId := (.value: UIntNative)

-- Intervals use the support curve's normalized parameter. A full circle or
-- ellipse is [0, 1]; values outside it are allowed on periodic supports.
CurveInterval := #(.Scalar: Type: Float) (.start: Scalar, .end: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(CurveInterval#(Scalar)) ()

-- A p-curve is attached to a halfedge use, not to its shared 3D edge. Its
-- parameter follows the canonical edge direction; reversal belongs to the use.
ParameterPoint := #(.Scalar: Type: Float) (.u: Scalar, .v: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(ParameterPoint#(Scalar)) ()

PCurve := #(.Scalar: Type: Float) (
    ..line(.start: ParameterPoint#(Scalar), .end: ParameterPoint#(Scalar)),
    ..harmonic(
        .origin : ParameterPoint#(Scalar),
        .linear : ParameterPoint#(Scalar),
        .cosine : ParameterPoint#(Scalar),
        .sine   : ParameterPoint#(Scalar),
        .start  : Scalar,
        .end    : Scalar
    ),
    ..ellipse(
        .center : ParameterPoint#(Scalar),
        .cosine : ParameterPoint#(Scalar),
        .sine   : ParameterPoint#(Scalar),
        .start  : Scalar,
        .end    : Scalar
    )
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(PCurve#(Scalar)) ()

pcurve_point := #(.Scalar: Type: Float) (.curve: PCurve#(Scalar), .parameter: Scalar) -> (
    .result : Errable#(ParameterPoint#(Scalar), BrepErrors)
) {
    if is_finite(parameter).ok == false or parameter < 0.0 or parameter > 1.0 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    validate_pcurve(curve)!
    value :: ParameterPoint#(Scalar) = (.u = 0.0, .v = 0.0)
    match curve {
        ..harmonic h {
            angle ::= [1.0 - parameter] * h.start + parameter * h.end
            c ::= cos(angle).result
            s ::= sin(angle).result
            value = (
                .u = h.origin.u + h.linear.u * angle + h.cosine.u * c + h.sine.u * s
                .v = [h.origin.v + h.linear.v * angle + h.cosine.v * c + h.sine.v * s]
            )
        }
        ..line line {
            value = (
                .u = [1.0 - parameter] * line.start.u + parameter * line.end.u
                .v = [1.0 - parameter] * line.start.v + parameter * line.end.v
            )
        }
        ..ellipse ellipse {
            angle ::= [1.0 - parameter] * ellipse.start + parameter * ellipse.end
            c ::= cos(angle).result
            s ::= sin(angle).result
            value = (
                .u = ellipse.center.u + ellipse.cosine.u * c + ellipse.sine.u * s
                .v = ellipse.center.v + ellipse.cosine.v * c + ellipse.sine.v * s
            )
        }
    }
    if is_finite(value.u).ok == false or is_finite(value.v).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok value
}

edge_interval := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .edge: EdgeId) -> (
    .result : Errable#(CurveInterval#(Scalar), (..out_of_bounds))
) {
    item ::= edge_info(model, .edge = edge)!
    match item.interval {
        ..none { result = ..ok(.start = 0.0, .end = 1.0) }
        ..some id {
            index ::= id.value | convert#(.to: UIntNative)(_)
            result = get(&model&._geometry.intervals, .index = index)
        }
    }
}

halfedge_parameters := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .halfedge: HalfEdgeId, .parameter: Scalar
) -> (.result: Errable#(ParameterPoint#(Scalar), BrepErrors)) {
    item ::= halfedge_info(model, .halfedge = halfedge)!
    match item.pcurve {
        ..none { result = ..error(.reason = ..unsupported_boundary) }
        ..some id {
            index ::= id.value | convert#(.to: UIntNative)(_)
            curve ::= get(&model&._geometry.pcurves, .index = index)!
            t :: Scalar = parameter
            if item.reversed { t = 1.0 - parameter }
            result = pcurve_point(.curve = curve, .parameter = t)
        }
    }
}

implement Convert#(UIntNative, PCurveId) (
    .Result  : Type = PCurveId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(PCurveId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: PCurveId) -> (.result: Result) { result = value.value }
)

implement Equal#(PCurveId, PCurveId) (
    .equal = (.left: PCurveId, .right: PCurveId) -> (.ok: Bool) {
        ok = left.value == right.value
    }
)

implement Convert#(UIntNative, CurveIntervalId) (
    .Result  : Type = CurveIntervalId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(CurveIntervalId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: CurveIntervalId) -> (.result: Result) { result = value.value }
)

implement Equal#(CurveIntervalId, CurveIntervalId) (
    .equal = (.left: CurveIntervalId, .right: CurveIntervalId) -> (.ok: Bool) {
        ok = [left.value == right.value]
    }
)

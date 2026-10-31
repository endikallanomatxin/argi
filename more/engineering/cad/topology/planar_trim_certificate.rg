-- Edge/surface compatibility is independent of region admission. For affine
-- segments two endpoint comparisons bound the entire corresponding interval.
_certify_planar_trim := #(.Scalar: Type: Float) (
    .plane     : g.Plane#(Scalar),
    .curve     : Curve#(Scalar),
    .interval  : CurveInterval#(Scalar),
    .pcurve    : PCurve#(Scalar),
    .tolerance : Scalar
) -> (.result: Errable#(Void, BrepErrors)) {
    support: g.Surface#(Scalar) = ..plane(.value = plane)
    match curve {
        ..circle _ {
            result = _certify_circular_trim(
                .surface   = support
                .curve     = curve
                .interval  = interval
                .pcurve    = pcurve
                .tolerance = tolerance
            )
        }
        ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
        ..segment _ {
            match pcurve {
                ..ellipse _ { result = ..error(.reason = ..unsupported_boundary) }
                ..harmonic _ { result = ..error(.reason = ..unsupported_boundary) }
                ..line line {
                    a ::= curve_point(.curve = curve, .parameter = interval.start)!
                    b ::= curve_point(.curve = curve, .parameter = interval.end)!
                    p ::= g.surface_point(
                        .surface = support, .u = line.start.u, .v = line.start.v
                    )!
                    q ::= g.surface_point(.surface = support, .u = line.end.u, .v = line.end.v)!
                    _trim_near_point(.a = a, .b = p, .tolerance = tolerance)!
                    _trim_near_point(.a = b, .b = q, .tolerance = tolerance)!
                    result = ..ok Void()
                }
            }
        }
    }
}

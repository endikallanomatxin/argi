-- Dispatch geometric certificates independently of topology construction.
-- Planar segments and circular arcs share the chart-region validator;
-- elliptic contours and periodic bands retain their analytic certificates.
_admit_trimmed_region := #(.Scalar: Type: Float) (
    .pools     : &_GeometryPools#(Scalar),
    .support   : g.Surface#(Scalar),
    .uses      : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .lengths   : ArrayView#(UIntNative),
    .reversed  : Bool,
    .tolerance : Scalar,
    .allocator : Virtual#(Allocator)
) -> (.result: Errable#(Void, BrepErrors)) {
    loops ::= length(&lengths).count
    match support {
        ..plane plane {
            count ::= length(uses).count
            circular_spans ::= true
            i :: UIntNative = 0
            while i < count {
                use ::= get(uses, .index = i)!
                match _pool_curve(pools, .curve = use.curve)! {
                    ..segment _ {}
                    ..circle _ {}
                    ..ellipse _ { circular_spans = false }
                }
                i = i + 1
            }
            if circular_spans {
                result = _admit_planar_contour_region(
                    .pools     = pools
                    .plane     = plane.value
                    .uses      = uses
                    .lengths   = lengths
                    .reversed  = reversed
                    .tolerance = tolerance
                    .allocator = allocator
                )
                return
            }
            first ::= get(uses, .index = 0)!
            curve ::= _pool_curve(pools, .curve = first.curve)!
            match curve {
                ..ellipse _ {
                    if loops != 1 {
                        result = ..error(.reason = ..unsupported_boundary)
                        return
                    }
                    count ::= get(&lengths, .index = 0)!
                    _admit_periodic_contour(.uses = uses, .start = 0, .count = count)!
                    i :: UIntNative = 0
                    while i < count {
                        _admit_planar_ellipse(
                            .pools     = pools
                            .plane     = plane.value
                            .use       = get(uses, .index = i)!
                            .reversed  = reversed
                            .tolerance = tolerance
                        )!
                        i = i + 1
                    }
                    result = ..ok Void()
                    return
                }
                ..circle _ {}
                ..segment _ {}
            }
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        ..sphere _ {
            if loops != 1 {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
        }
        ..cylinder c {
            value: g.Cylinder#(Scalar) = (.frame = c.frame, .radius = c.radius)
            result = _admit_cylinder_band(
                .pools     = pools
                .surface   = value
                .uses      = uses
                .lengths   = lengths
                .reversed  = reversed
                .tolerance = tolerance
            )
            return
        }
        ..torus t {
            value: g.Torus#(Scalar) = (
                .frame        = t.frame
                .major_radius = t.major_radius
                .minor_radius = t.minor_radius
            )
            result = _admit_torus_band(
                .pools     = pools
                .surface   = value
                .uses      = uses
                .lengths   = lengths
                .reversed  = reversed
                .tolerance = tolerance
            )
            return
        }
    }
    start :: UIntNative = 0
    l :: UIntNative = 0
    while l < loops {
        count ::= get(&lengths, .index = l)!
        first ::= get(uses, .index = start)!
        curve ::= _pool_curve(pools, .curve = first.curve)!
        match curve {
            ..ellipse _ {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
            ..segment _ {
                result = ..error(.reason = ..unsupported_boundary)
                return
            }
            ..circle _ {}
        }
        _admit_periodic_contour(.uses = uses, .start = start, .count = count)!
        i :: UIntNative = 0
        while i < count {
            use ::= get(uses, .index = start + i)!
            _certify_circular_trim(
                .surface   = support
                .curve     = curve
                .interval  = use.interval
                .pcurve    = use.pcurve
                .tolerance = tolerance
            )!
            i = i + 1
        }
        start = start + count
        l = l + 1
    }
    result = ..ok Void()
}

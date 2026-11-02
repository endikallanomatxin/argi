-- Keys are positions in this profile's region/contour views, not model IDs.
-- Boundary includes exterior and hole boundaries within modeling tolerance.
ProfileLocation := (
    ..outside,
    ..inside(.region: UIntNative),
    ..boundary(.region: UIntNative, .contour: UIntNative)
)

implement ImplicitlyCopyable#(ProfileLocation) ()

-- Classify a world point without publishing a B-rep or allocating scratch.
-- Points within plane tolerance are projected into the profile chart; points
-- farther from its plane are outside. Analytic spans use the common classifier.
locate_in_profile := #(.Scalar: Type: Float) (
    .profile: &PlanarProfile#(Scalar), .point: g.Point#(Scalar)
) -> (.result: Errable#(ProfileLocation, g.GeometryErrors)) {
    if g.finite_point(point).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    offset ::= g.between(.from = profile&._frame.origin, .to = point).result
    distance ::= g.dot(.left = profile&._frame.z, .right = offset).value
    if is_finite(distance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if distance > profile&._tolerance or distance < [0.0 - profile&._tolerance] {
        result = ..ok ..outside
        return
    }
    local ::= _profile_chart_point(.frame = profile&._frame, .point = point)!
    spans ::= view(&profile&._spans)
    regions ::= length(&profile&._region_lengths).count
    region :: UIntNative = 0
    contour :: UIntNative = 0
    first :: UIntNative = 0
    while region < regions {
        count ::= get(&profile&._region_lengths, .index = region)!
        loop :: UIntNative = 0
        inside ::= false
        while loop < count {
            length ::= get(&profile&._contour_lengths, .index = contour)!
            boundary ::= slice(&spans, .start = first, .count = length)!
            location ::= g.locate_in_contour_spans(
                .spans = boundary, .point = local, .tolerance = profile&._tolerance
            )!
            match location {
                ..boundary {
                    result = ..ok ..boundary(.region = region, .contour = contour)
                    return
                }
                ..inside { if loop == 0 { inside = true } else { inside = false } }
                ..outside {}
            }
            first = first + length
            contour = contour + 1
            loop = loop + 1
        }
        if inside {
            result = ..ok ..inside(.region = region)
            return
        }
        region = region + 1
    }
    result = ..ok ..outside
}

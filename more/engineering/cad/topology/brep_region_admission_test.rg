_closed_planar_circle_use := #(.Scalar: Type: Float) (
    .builder   : $&BrepBuilder#(Scalar),
    .frame     : g.Frame#(Scalar),
    .center    : ParameterPoint#(Scalar),
    .radius    : Scalar,
    .reversed  : Bool,
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(TrimUse#(Scalar), BrepErrors)) {
    basis: g.Frame#(Scalar) = (
        .origin = (
            .x = frame.origin.x + frame.x.x * center.u + frame.y.x * center.v
            .y = frame.origin.y + frame.x.y * center.u + frame.y.y * center.v
            .z = frame.origin.z + frame.x.z * center.u + frame.y.z * center.v
        )
        .x = frame.x
        .y = frame.y
        .z = frame.z
    )
    curve: Curve#(Scalar) = ..circle(.value = (.frame = basis, .radius = radius))
    support ::= builder | declare_curve(_, .curve = curve, .allocator = allocator)!
    edge ::= builder | declare_closed_edge(_, .curve = support, .allocator = allocator)!
    pcurve: PCurve#(Scalar) = ..ellipse(
        .center = center
        .cosine = (.u = radius, .v = 0.0)
        .sine   = (.u = 0.0, .v = radius)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    result = ..ok(.edge = edge, .pcurve = pcurve, .reversed = reversed)
}

_two_circular_holes := #(.Scalar: Type: Float) (
    .allocator: $&Virtual#(Allocator), .second_offset: Scalar = 2.0
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    basis ::= g.frame#(Scalar)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    plane: g.Surface#(Scalar) = ..plane(
        .value = (.origin = basis.origin, .normal = basis.z)
    )
    surface ::= builder | declare_surface($&_, .surface = plane, .allocator = allocator)!
    exterior ::= _closed_planar_circle_use(
        $&builder
        .frame     = basis
        .center    = (.u = 0.0, .v = 0.0)
        .radius    = 5.0
        .reversed  = false
        .allocator = allocator
    )!
    first ::= _closed_planar_circle_use(
        $&builder
        .frame     = basis
        .center    = (.u = -2.0, .v = 0.0)
        .radius    = 1.0
        .reversed  = true
        .allocator = allocator
    )!
    second ::= _closed_planar_circle_use(
        $&builder
        .frame     = basis
        .center    = (.u = second_offset, .v = 0.0)
        .radius    = 1.0
        .reversed  = true
        .allocator = allocator
    )!
    uses: [3]TrimUse#(Scalar) = (exterior, first, second)
    lengths: [3]UIntNative = (1, 1, 1)
    declare_trimmed_face(
        $&builder
        .surface         = surface
        .boundaries      = view(&uses)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    model ::= builder | finish_brep(~_, .require_closed = false, .allocator = allocator)!
    result = ..ok ~model
}

test model_curved_region_multiple_holes := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    model ::= _two_circular_holes#(.Scalar: Float64)(.allocator = allocator)!
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                counts.loops == 3
                and counts.faces == 1
                and counts.vertices == 0
                and counts.edges == 3
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = -2.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    inverted ::= reverse_orientation(&model)!
    [
        testing.expect(
            [face_contains_parameters(&inverted, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&inverted, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _two_circular_holes#(.Scalar: Float64)(
                .allocator = allocator, .second_offset = -1.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _two_circular_holes#(.Scalar: Float64)(
                .allocator = allocator, .second_offset = 0.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
}

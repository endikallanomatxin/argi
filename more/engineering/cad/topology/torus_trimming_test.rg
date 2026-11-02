_torus_band := #(.Scalar: Type: Float) (
    .allocator     : Virtual#(Allocator),
    .lower         : Scalar      = 5.5,
    .upper         : Scalar      = 7.0,
    .wrong_radius  : Bool        = false,
    .reverse_upper : Bool        = true
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    basis ::= g.frame#(Scalar)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    support: g.Surface#(Scalar) = ..torus(
        .frame        = basis
        .major_radius = 3.0
        .minor_radius = 1.0
    )
    surface ::= builder | declare_surface($&_, .surface = support, .allocator = allocator)!
    levels: [2]Scalar = (lower, upper)
    uses ::= DynamicArray#(TrimUse#(Scalar))(.allocator = allocator, .capacity = 2)!
    i :: UIntNative = 0
    while i < 2 {
        v ::= levels[i]
        frame: g.Frame#(Scalar) = (
            .origin = (.x = 0.0, .y = 0.0, .z = sin(v).result)
            .x      = basis.x
            .y      = basis.y
            .z      = basis.z
        )
        radius ::= 3.0 + cos(v).result
        if wrong_radius and i == 1 { radius = radius + 0.1 }
        curve: Curve#(Scalar) = ..circle(.value = (.frame = frame, .radius = radius))
        id ::= builder | declare_curve($&_, .curve = curve, .allocator = allocator)!
        edge ::= builder | declare_closed_edge($&_, .curve = id, .allocator = allocator)!
        pcurve: PCurve#(Scalar) = ..line(
            .start = (.u = 0.0, .v = v)
            .end   = (.u = 6.283185307179586, .v = v)
        )
        use: TrimUse#(Scalar) = (
            .edge     = edge
            .pcurve   = pcurve
            .reversed = [i == 1 and reverse_upper]
        )
        push_assume_capacity($&uses, .value = use)
        i = i + 1
    }
    lengths: [2]UIntNative = (1, 1)
    declare_trimmed_face(
        $&builder
        .surface         = surface
        .boundaries      = view(&uses)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    result = [builder | finish_brep(~_, .require_closed = false, .allocator = allocator)]
}

test model_torus_band_crosses_both_periods_without_seams := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _torus_band#(.Scalar: Float64)(.allocator = allocator)!
    inverse ::= reverse_orientation(&model)!
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                counts.vertices == 0
                and counts.edges == 2
                and counts.faces == 1
                and counts.loops == 2
            ]
        )!
    ]
    testing.expect(is_closed(&model).ok == false)!
    for loop in [face_loops(&model, .face = (.value = 0))!] {
        for use in [loop_halfedges(&model, .loop = loop.id)!] {
            t :: Float64 = 0.0
            while t <= 1.0 {
                uv ::= halfedge_parameters(&model, .halfedge = use.id, .parameter = t)!
                p ::= halfedge_point(&model, .halfedge = use.id, .parameter = t)!
                q ::= [
                    g.surface_point(
                        .surface = [face_surface(&model, .face = (.value = 0))!]
                        .u       = uv.u
                        .v       = uv.v
                    )!
                ]
                [_trim_near_point(.a = p, .b = q, .tolerance = 0.000001)!]
                t = t + 0.125
            }
        }
    }
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = -0.25, .v = 0.25)!]
        )!
    ]
    [
        testing.expect(
            [
                face_contains_parameters(
                    &model, .face = (.value = 0), .u = 7.0, .v = 6.533185307179586
                )!
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&inverse, .face = (.value = 0), .u = 7.0, .v = 0.25)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 3.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 5.5)!]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 7.0)!]
        )!
    ]
}

test model_torus_band_float32_and_admission_errors := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _torus_band#(.Scalar: Float32)(.allocator = allocator)!
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = -7.0, .v = 0.25)!]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _torus_band#(.Scalar: Float64)(
                .allocator = allocator, .wrong_radius = true
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _torus_band#(.Scalar: Float64)(
                .allocator = allocator, .upper = 5.0
            )
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _torus_band#(.Scalar: Float64)(
                .allocator = allocator, .upper = 12.0
            )
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _torus_band#(.Scalar: Float64)(
                .allocator = allocator, .reverse_upper = false
            )
            .expected_reason = ..inconsistent_orientation
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _torus_band#(.Scalar: Float64)(
                .allocator = allocator, .upper = 5.50000001
            )
            .expected_reason = ..numerical_ambiguity
        )!
    ]
}

test model_torus_band_periodic_classification_uncertainty := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _torus_band#(.Scalar: Float64)(.allocator = allocator)!
    [
        testing.expect_error(
            .actual_result = face_contains_parameters(
                &model, .face = (.value = 0), .u = 0.0, .v = 1.0e100
            )
            .expected_reason = ..numerical_ambiguity
        )!
    ]
    shifted_boundary: Float64 = 11.783185307179586
    [
        testing.expect_error(
            .actual_result = face_contains_parameters(
                &model, .face = (.value = 0), .u = 0.0, .v = shifted_boundary
            )
            .expected_reason = ..numerical_ambiguity
        )!
    ]
    shifted_interior: Float64 = -0.283185307179586
    [
        testing.expect(
            [
                face_contains_parameters(
                    &model, .face = (.value = 0), .u = -6.283185307179586, .v = shifted_interior
                )!
            ]
        )!
    ]
}

-- A property shared by every admitted analytic family, independent of the
-- individual construction certificates. No production differentiation by secants.
_check_boundary_chain_rule := #(.Scalar: Type: Float) (.model: &Model#(Scalar)) -> !Void {

    parameters: [5]Scalar = (0.0, 0.125, 0.5, 0.875, 1.0)
    f :: UIntNative = 0
    while f < entity_counts(model).faces {
        face ::= f | convert#(.to: FaceId)(_)
        support ::= face_surface(model, .face = face)!
        for loop in [face_loops(model, .face = face)!] {
            for use in [loop_halfedges(model, .loop = loop.id)!] {
                for parameter in parameters {
                    uv ::= [
                        halfedge_parameters(model, .halfedge = use.id, .parameter = parameter)!
                    ]
                    rate ::= [
                        halfedge_parameter_derivative(
                            model, .halfedge = use.id, .parameter = parameter
                        )!
                    ]
                    partials ::= [
                        g.surface_derivatives(.surface = support, .u = uv.u, .v = uv.v)!
                    ]
                    lifted: g.Displacement#(Scalar) = (
                        .x = partials.du.x * rate.u + partials.dv.x * rate.v
                        .y = partials.du.y * rate.u + partials.dv.y * rate.v
                        .z = partials.du.z * rate.u + partials.dv.z * rate.v
                    )
                    direct ::= [
                        halfedge_derivative(model, .halfedge = use.id, .parameter = parameter)!
                    ]
                    [
                        _expect_curve_derivative(
                            .actual = direct, .expected = lifted, .tolerance = 0.0001
                        )!
                    ]
                    p ::= halfedge_point(model, .halfedge = use.id, .parameter = parameter)!
                    q ::= g.surface_point(.surface = support, .u = uv.u, .v = uv.v)!
                    [
                        testing.expect(
                            [g.norm(g.between(.from = p, .to = q).result).value < 0.00001]
                        )!
                    ]
                    normal ::= face_normal(model, .face = face, .u = uv.u, .v = uv.v)!
                    alignment ::= g.dot(.left = normal, .right = direct).value
                    [
                        testing.expect(
                            [
                                alignment < 0.0001 * [1.0 + g.norm(direct).value]
                                and alignment > -0.0001 * [1.0 + g.norm(direct).value]
                            ]
                        )!
                    ]
                    match [opposite(model, .halfedge = use.id)!] {
                        ..none {}
                        ..some other {
                            reverse ::= [
                                halfedge_derivative(
                                    model
                                    .halfedge  = other.value
                                    .parameter = [1.0 - parameter]
                                )!
                            ]
                            negative: g.Displacement#(Scalar) = (
                                .x = 0.0 - direct.x
                                .y = [0.0 - direct.y]
                                .z = [0.0 - direct.z]
                            )
                            [
                                _expect_curve_derivative(
                                    .actual = reverse, .expected = negative, .tolerance = 0.0001
                                )!
                            ]
                        }
                    }
                }
            }
        }
        f = f + 1
    }
    result = ..ok Void()
}

_check_reversed_boundary_differentials := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .allocator: Virtual#(Allocator)
) -> !Void {

    inverse ::= reverse_orientation(model, .allocator = allocator)!
    [_check_boundary_chain_rule(.model = model)!]
    [_check_boundary_chain_rule(.model = &inverse)!]
    parameters: [3]Scalar = (0.0, 0.3, 1.0)
    i :: UIntNative = 0
    while i < entity_counts(model).halfedges {
        id ::= i | convert#(.to: HalfEdgeId)(_)
        for parameter in parameters {
            before ::= halfedge_derivative(model, .halfedge = id, .parameter = parameter)!
            after ::= [
                halfedge_derivative(&inverse, .halfedge = id, .parameter = 1.0 - parameter)!
            ]
            negative: g.Displacement#(Scalar) = (
                .x = 0.0 - before.x
                .y = 0.0 - before.y
                .z = [0.0 - before.z]
            )
            [
                _expect_curve_derivative(
                    .actual = after, .expected = negative, .tolerance = 0.0001
                )!
            ]
            uv_before ::= [
                halfedge_parameter_derivative(model, .halfedge = id, .parameter = parameter)!
            ]
            uv_after ::= [
                halfedge_parameter_derivative(
                    &inverse, .halfedge = id, .parameter = [1.0 - parameter]
                )!
            ]
            delta ::= hypot(
                .left = uv_before.u + uv_after.u, .right = uv_before.v + uv_after.v
            ).result
            speed ::= hypot(.left = uv_before.u, .right = uv_before.v).result
            testing.expect(delta < 0.0001 * [1.0 + speed])!
        }
        i = i + 1
    }
    result = ..ok Void()
}

test model_differentials_mixed_planar_boundaries_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= [
        _mixed_planar_face#(.Scalar: Float64)(
            .allocator = allocator, .rotate = true, .renumber = true
        )!
    ]
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_mixed_planar_boundaries_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _mixed_planar_face#(.Scalar: Float32)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_sphere_shared_circular_boundary_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _brep_hemisphere#(.Scalar: Float64)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_sphere_shared_circular_boundary_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _brep_hemisphere#(.Scalar: Float32)(.allocator = allocator, .north = false)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_partitioned_oblique_cylinder_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _partitioned_oblique_cylinder#(.Scalar: Float64)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_partitioned_oblique_cylinder_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _partitioned_oblique_cylinder#(.Scalar: Float32)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_torus_band_crossing_periods_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _torus_band#(.Scalar: Float64)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_torus_band_crossing_periods_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _torus_band#(.Scalar: Float32)(.allocator = allocator)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

test model_differentials_reject_missing_pcurves_and_invalid_use_queries := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _brep_hemisphere#(.Scalar: Float64)(.allocator = allocator)!
    [
        testing.expect_error(
            .actual_result = halfedge_derivative(
                &model, .halfedge = (.value = 0), .parameter = 1.1
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result = halfedge_parameter_derivative(
                &model, .halfedge = (.value = 0), .parameter = 1.1
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result = halfedge_derivative(
                &model, .halfedge = (.value = 10), .parameter = 0.5
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result = halfedge_parameter_derivative(
                &model, .halfedge = (.value = 10), .parameter = 0.5
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    points: [3]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    faces: [1][3]UIntNative = ((0, 1, 2))
    polygon ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    derivative ::= halfedge_derivative(&polygon, .halfedge = (.value = 0), .parameter = 0.5)!
    testing.expect(derivative.x == 1.0 and derivative.y == 0.0 and derivative.z == 0.0)!
    [
        testing.expect_error(
            .actual_result = halfedge_parameter_derivative(
                &polygon, .halfedge = (.value = 0), .parameter = 0.5
            )
            .expected_reason = ..unsupported_boundary
        )!
    ]
}

test model_differentials_segment_subinterval_uses_its_own_parameter := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    builder ::= BrepBuilder#(Float64)()!
    a ::= builder | declare_vertex($&_, .point = (1.0, 0.0, 0.0))!
    b ::= builder | declare_vertex($&_, .point = (3.0, 0.0, 0.0))!
    c ::= builder | declare_vertex($&_, .point = (1.0, 1.0, 0.0))!
    ab_support: Curve#(Float64) = ..segment(
        .start = (0.0, 0.0, 0.0)
        .end   = (4.0, 0.0, 0.0)
    )
    bc_support: Curve#(Float64) = ..segment(
        .start = (3.0, 0.0, 0.0)
        .end   = (1.0, 1.0, 0.0)
    )
    ca_support: Curve#(Float64) = ..segment(
        .start = (1.0, 1.0, 0.0)
        .end   = (1.0, 0.0, 0.0)
    )
    ab_curve ::= builder | declare_curve($&_, .curve = ab_support)!
    bc_curve ::= builder | declare_curve($&_, .curve = bc_support)!
    ca_curve ::= builder | declare_curve($&_, .curve = ca_support)!
    ab ::= [
        declare_edge(
            $&builder
            .curve    = ab_curve
            .interval = (.start = 0.25, .end = 0.75)
            .start    = a
            .end      = b
        )!
    ]
    bc ::= [
        declare_edge(
            $&builder
            .curve    = bc_curve
            .interval = (.start = 0.0, .end = 1.0)
            .start    = b
            .end      = c
        )!
    ]
    ca ::= [
        declare_edge(
            $&builder
            .curve    = ca_curve
            .interval = (.start = 0.0, .end = 1.0)
            .start    = c
            .end      = a
        )!
    ]
    plane: g.Surface#(Float64) = ..plane(
        .value = (
            .origin = (0.0, 0.0, 0.0)
            .normal = (0.0, 0.0, 1.0)
        )
    )
    surface ::= builder | declare_surface($&_, .surface = plane)!
    -- Plane chart x=-Y, y=X. The p-curve already spans the trimmed [1,3].
    uses: [3]TrimUse#(Float64) = (
        (
            .edge   = ab
            .pcurve = ..line(.start = (.u = 0.0, .v = 1.0), .end = (.u = 0.0, .v = 3.0))
        ),
        (
            .edge   = bc
            .pcurve = ..line(.start = (.u = 0.0, .v = 3.0), .end = (.u = -1.0, .v = 1.0))
        ),
        (
            .edge   = ca
            .pcurve = ..line(.start = (.u = -1.0, .v = 1.0), .end = (.u = 0.0, .v = 1.0))
        )
    )
    lengths: [1]UIntNative = (3)
    [
        declare_trimmed_face(
            $&builder
            .surface         = surface
            .boundaries      = view(&uses)
            .contour_lengths = view(&lengths)
        )!
    ]
    model ::= builder | finish_brep(~_, .require_closed = false)!
    derivative ::= halfedge_derivative(&model, .halfedge = (.value = 0), .parameter = 0.5)!
    rate ::= halfedge_parameter_derivative(&model, .halfedge = (.value = 0), .parameter = 0.5)!
    testing.expect(derivative.x == 2.0 and derivative.y == 0.0 and derivative.z == 0.0)!
    testing.expect(rate.u == 0.0 and rate.v == 2.0)!
    [_check_reversed_boundary_differentials(.model = &model, .allocator = allocator)!]
}

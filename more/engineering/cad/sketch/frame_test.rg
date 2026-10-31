test sketch_frame_preserves_arbitrary_placement_through_publication_and_extrusion := (
    .system : System
) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    frame: g.Frame#(Float64) = (
        .origin = (3.0, 4.0, 5.0)
        .x      = (0.8, 0.0, -0.6)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.6, 0.0, 0.8)
    )
    builder ::= sketch_builder_on_frame(.frame = frame)!
    exterior ::= builder | rectangle($&_, .width = 4.0, .height = 2.0)!
    builder | circle($&_, .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    selection ::= profile_with_history(&drawing, .exterior = exterior)!
    publication ::= m.profile_brep_with_history(&selection.profile)!
    face ::= m.published_profile_face(&publication, .region = 0)!
    normal ::= [t.face_plane(&publication.model, .face = face)!].normal
    testing.expect(g.dot(.left = normal, .right = frame.z).value > 0.999999)!
    corner ::= m.profile_point(&selection.profile, .index = 0)!
    expected: g.Point#(Float64) = (1.4, 3.0, 6.2)
    testing.expect(g.norm(g.between(.from = expected, .to = corner).result).value < 0.000001)!
    use ::= m.published_profile_halfedge(&publication, .span = 4)!
    angle: Float64 = 1.5707963267948966
    actual ::= t.halfedge_point(&publication.model, .halfedge = use, .parameter = 0.25)!
    circle_point: g.Point#(Float64) = (
        .x = [
            frame.origin.x
            + frame.x.x * 0.25 * cos(angle).result
            - frame.y.x * 0.25 * sin(angle).result
        ]
        .y = [
            frame.origin.y
            + frame.x.y * 0.25 * cos(angle).result
            - frame.y.y * 0.25 * sin(angle).result
        ]
        .z = [
            frame.origin.z
            + frame.x.z * 0.25 * cos(angle).result
            - frame.y.z * 0.25 * sin(angle).result
        ]
    )
    [
        testing.expect(
            g.norm(g.between(.from = circle_point, .to = actual).result).value < 0.000001
        )!
    ]
    chosen: [1]ContourRef = (exterior)
    plain ::= profile_from_contours(&drawing, .contours = view(&chosen))!
    extrusion ::= [
        m.extrude_with_history(.profile = &plain, .displacement = (1.2, 0.0, 1.6))!
    ]
    caps ::= m.extrusion_caps(&extrusion, .region = 0)!
    testing.expect(t.is_closed(&extrusion.model).ok)!
    [
        testing.expect(
            [
                g.dot(
                    .left  = [t.face_plane(&extrusion.model, .face = caps.end)!].normal
                    .right = frame.z
                ).value
                > 0.999999
            ]
        )!
    ]
}

test sketch_frame_rejects_scale_reflection_and_skew := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    frame ::= [
        g.frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    scaled ::= frame
    scaled.x = (2.0, 0.0, 0.0)
    [
        testing.expect_error(
            .actual_result   = sketch_builder_on_frame(.frame = scaled)
            .expected_reason = ..degenerate_face
        )!
    ]
    reflected ::= frame
    reflected.z = (0.0, 0.0, -1.0)
    [
        testing.expect_error(
            .actual_result   = sketch_builder_on_frame(.frame = reflected)
            .expected_reason = ..degenerate_face
        )!
    ]
    skew ::= frame
    skew.y = skew.x
    [
        testing.expect_error(
            .actual_result   = sketch_builder_on_frame(.frame = skew)
            .expected_reason = ..degenerate_face
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = sketch_builder_on_frame(.frame = frame, .tolerance = 0.0)
            .expected_reason = ..invalid_tolerance
        )!
    ]
    builder ::= sketch_builder_on_frame(.frame = frame)!
    builder | rectangle($&_, .width = 2.0, .height = 1.0)!
    drawing ::= builder | finish_sketch(~_)!
    testing.expect(contour_count(&drawing).count == 1)!
}

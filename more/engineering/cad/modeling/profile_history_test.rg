test extrusion_profile_history_tracks_directed_arcs_and_holes := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    frame ::= [
        g.frame#(Float64)(.origin = (3.0, 4.0, 5.0), .axis = (0.0, -1.0, 0.0))!
    ]
    spans: [3]g.ContourSpan#(Float64) = (
        (
            .start = (2.0, 0.0)
            .end   = (-2.0, 0.0)
            .sweep = 3.141592653589793
        ),
        (
            .start = (-2.0, 0.0)
            .end   = (2.0, 0.0)
            .sweep = 3.141592653589793
        ),
        (
            .start = (0.5, 0.0)
            .end   = (0.5, 0.0)
            .sweep = -6.283185307179586
        )
    )
    lengths: [2]UIntNative = (2, 1)
    profile ::= [
        profile_from_spans(
            .spans = view(&spans), .contour_lengths = view(&lengths), .frame = frame
        )!
    ]
    publication ::= profile_brep_with_history(&profile)!
    face ::= published_profile_face(&publication, .region = 0)!
    [
        testing.expect([[t.face_info(&publication.model, .face = face)!].loop_count == 2])!
    ]
    i :: UIntNative = 0
    while i < 3 {
        use ::= published_profile_halfedge(&publication, .span = i)!
        contour :: UIntNative = 0
        if i == 2 { contour = 1 }
        loop ::= published_profile_loop(&publication, .contour = contour)!
        info ::= t.halfedge_info(&publication.model, .halfedge = use)!
        testing.expect(info.loop == loop)!
        parameter :: Float64 = 0.0
        while parameter <= 1.0 {
            angle ::= spans[i].sweep * parameter
            local: g.ContourPoint#(Float64) = (
                .x = spans[i].start.x * cos(angle).result
                .y = spans[i].start.x * sin(angle).result
            )
            expected ::= _profile_world_point(.frame = frame, .point = local).value
            actual ::= [
                t.halfedge_point(&publication.model, .halfedge = use, .parameter = parameter)!
            ]
            [
                testing.expect(
                    [g.norm(g.between(.from = expected, .to = actual).result).value < 0.000001]
                )!
            ]
            parameter = parameter + 0.25
        }
        i = i + 1
    }
    [
        testing.expect_error(
            .actual_result   = published_profile_face(&publication, .region = 1)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = published_profile_loop(&publication, .contour = 2)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = published_profile_halfedge(&publication, .span = 3)
            .expected_reason = ..out_of_bounds
        )!
    ]
}

_history_without_source := (.allocator: $&Virtual#(Allocator)) -> (
    .result : Errable#(ProfilePublication#(Float32), t.BrepErrors)
) {
    points: [6]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    lengths: [2]UIntNative = (3, 3)
    regions: [2]UIntNative = (1, 1)
    profile ::= planar_profile(
        .points          = view(&points)
        .contour_lengths = view(&lengths)
        .region_lengths  = view(&regions)
        .allocator       = allocator
    )!
    publication ::= profile_brep_with_history(&profile, .allocator = allocator)!
    result = ..ok ~publication
}

test extrusion_profile_history_owns_disconnected_float32_images := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    publication ::= _history_without_source(.allocator = allocator)!
    region :: UIntNative = 0
    while region < 2 {
        face ::= published_profile_face(&publication, .region = region)!
        loop ::= published_profile_loop(&publication, .contour = region)!
        [
            testing.expect([[t.face_loop(&publication.model, .face = face)!] == loop])!
        ]
        i :: UIntNative = 0
        for entry in [t.loop_halfedges(&publication.model, .loop = loop)!] {
            mapped ::= published_profile_halfedge(&publication, .span = region * 3 + i)!
            testing.expect(mapped == entry.id)!
            i = i + 1
        }
        testing.expect(i == 3)!
        region = region + 1
    }
}

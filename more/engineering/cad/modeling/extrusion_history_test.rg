test extrusion_history_tracks_oblique_caps_and_every_wall := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [8]g.Point#(Float64) = (
        (-3.0, -2.0, 0.0),
        (3.0, -2.0, 0.0),
        (3.0, 2.0, 0.0),
        (-3.0, 2.0, 0.0),
        (-1.0, -1.0, 0.0),
        (1.0, -1.0, 0.0),
        (1.0, 1.0, 0.0),
        (-1.0, 1.0, 0.0)
    )
    lengths: [2]UIntNative = (4, 4)
    regions: [1]UIntNative = (2)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&lengths)
            .region_lengths  = view(&regions)
        )!
    ]
    heights: [2]Float64 = (2.0, -2.0)
    for height in heights {
        extrusion ::= [
            extrude_with_history(.profile = &profile, .displacement = (0.25, 0.5, height))!
        ]
        caps ::= extrusion_caps(&extrusion, .region = 0)!
        testing.expect(t.is_closed(&extrusion.model).ok)!
        [
            testing.expect(
                [[t.face_info(&extrusion.model, .face = caps.start)!].loop_count == 2]
            )!
        ]
        [
            testing.expect([[t.face_info(&extrusion.model, .face = caps.end)!].loop_count == 2])!
        ]
        start_normal ::= t.face_plane(&extrusion.model, .face = caps.start)!.normal
        testing.expect(start_normal.z * height < 0.0)!
        end_normal ::= t.face_plane(&extrusion.model, .face = caps.end)!.normal
        testing.expect(end_normal.z * height > 0.0)!
        i :: UIntNative = 0
        while i < 8 {
            wall ::= extrusion_wall(&extrusion, .span = i)!
            a ::= profile_point(&profile, .index = i)!
            span ::= get(&profile._spans, .index = i)!
            b ::= _profile_world_point(.frame = profile._frame, .point = span.end).value
            plane ::= t.face_plane(&extrusion.model, .face = wall)!
            translated: g.Point#(Float64) = (
                .x = a.x + 0.25
                .y = a.y + 0.5
                .z = a.z + height
            )
            samples: [3]g.Point#(Float64) = (a, b, translated)
            for sample in samples {
                distance ::= g.dot(
                    .left  = plane.normal
                    .right = g.between(.from = plane.origin, .to = sample).result
                ).value
                testing.expect(distance > -0.000001 and distance < 0.000001)!
            }
            expected ::= g.cross(
                .left = g.between(.from = a, .to = b).result, .right = (0.25, 0.5, height)
            ).result
            alignment ::= g.dot(.left = plane.normal, .right = expected).value * height
            testing.expect(alignment > 0.0)!
            i = i + 1
        }
        [
            testing.expect_error(
                .actual_result   = extrusion_caps(&extrusion, .region = 1)
                .expected_reason = ..out_of_bounds
            )!
        ]
        [
            testing.expect_error(
                .actual_result   = extrusion_wall(&extrusion, .span = 8)
                .expected_reason = ..out_of_bounds
            )!
        ]
    }
}

_extrusion_history_without_source := (.allocator: Virtual#(Allocator)) -> (
    .result : Errable#(ExtrusionResult#(Float32), t.BrepErrors)
) {
    points: [6]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    contours: [2]UIntNative = (3, 3)
    regions: [2]UIntNative = (1, 1)
    profile ::= planar_profile(
        .points          = view(&points)
        .contour_lengths = view(&contours)
        .region_lengths  = view(&regions)
        .allocator       = allocator
    )!
    built ::= extrude_with_history(
        .profile = &profile, .displacement = (0.0, 0.0, 1.0), .allocator = allocator
    )!
    result = ..ok ~built
}

test extrusion_history_owns_disconnected_float32_images := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    extrusion ::= _extrusion_history_without_source(.allocator = allocator)!
    testing.expect(t.entity_counts(&extrusion.model).faces == 10)!
    region :: UIntNative = 0
    while region < 2 {
        caps ::= extrusion_caps(&extrusion, .region = region)!
        minimum :: Float32 = 0.0
        if region == 1 { minimum = 3.0 }
        faces: [2]t.FaceId = (caps.start, caps.end)
        for face in faces {
            loop ::= t.face_loop(&extrusion.model, .face = face)!
            for use in [t.loop_halfedges(&extrusion.model, .loop = loop)!] {
                p ::= t.halfedge_point(&extrusion.model, .halfedge = use.id, .parameter = 0.0)!
                testing.expect(p.x >= minimum and p.x <= minimum + 1.0)!
            }
        }
        region = region + 1
    }
}

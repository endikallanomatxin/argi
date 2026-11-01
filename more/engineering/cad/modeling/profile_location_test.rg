test profile_location_classifies_arcs_holes_and_plane_tolerance := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    frame: g.Frame#(Float64) = (
        .origin = (3.0, 4.0, 5.0)
        .x      = (0.8, 0.0, -0.6)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.6, 0.0, 0.8)
    )
    spans: [3]g.ContourSpan#(Float64) = (
        (.start = (-3.0, 0.0), .end = (3.0, 0.0)),
        (
            .start = (3.0, 0.0)
            .end   = (-3.0, 0.0)
            .sweep = 3.141592653589793
        ),
        (
            .start  = (0.5, 1.0)
            .end    = (0.5, 1.0)
            .center = (0.0, 1.0)
            .sweep  = -6.283185307179586
        )
    )
    lengths: [2]UIntNative = (2, 1)
    profile ::= [
        profile_from_spans(
            .spans = view(&spans), .contour_lengths = view(&lengths), .frame = frame
        )!
    ]
    local: [7]g.ContourPoint#(Float64) = (
        (0.0, 2.0),
        (0.0, 1.0),
        (0.0, -1.0),
        (0.0, 0.0),
        (0.0, 3.0),
        (0.5, 1.0),
        (3.0, 0.0)
    )
    expected: [7]UIntNative = (1, 0, 0, 2, 2, 2, 2)
    i :: UIntNative = 0
    while i < 7 {
        point ::= _profile_world_point(.frame = frame, .point = local[i]).value
        actual ::= locate_in_profile(&profile, .point = point)!
        match actual {
            ..outside { [testing.expect(expected[i] == 0)!] }
            ..inside found {
                testing.expect(expected[i] == 1 and found.region == 0)!
            }
            ..boundary found {
                contour :: UIntNative = 0
                if i == 5 { contour = 1 }
                [
                    testing.expect(
                        [expected[i] == 2 and found.region == 0 and found.contour == contour]
                    )!
                ]
            }
        }
        i = i + 1
    }
    offsets: [2]Float64 = (0.0000005, 0.000002)
    for offset in offsets {
        point: g.Point#(Float64) = (
            .x = 3.0 + frame.z.x * offset
            .y = 6.0
            .z = [5.0 + frame.z.z * offset]
        )
        actual ::= locate_in_profile(&profile, .point = point)!
        match actual {
            ..inside _ { [testing.expect(offset < 0.000001)!] }
            ..outside { [testing.expect(offset > 0.000001)!] }
            ..boundary _ { [testing.fail()!] }
        }
    }
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result   = locate_in_profile(&profile, .point = (nan, 0.0, 0.0))
            .expected_reason = ..invalid_coordinate
        )!
    ]
}

test profile_location_distinguishes_disconnected_region_and_island := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [12]g.Point#(Float32) = (
        (-2.0, -2.0, 0.0),
        (2.0, -2.0, 0.0),
        (2.0, 2.0, 0.0),
        (-2.0, 2.0, 0.0),
        (-1.0, -1.0, 0.0),
        (1.0, -1.0, 0.0),
        (1.0, 1.0, 0.0),
        (-1.0, 1.0, 0.0),
        (-0.25, -0.25, 0.0),
        (0.25, -0.25, 0.0),
        (0.25, 0.25, 0.0),
        (-0.25, 0.25, 0.0)
    )
    lengths: [3]UIntNative = (4, 4, 4)
    regions: [2]UIntNative = (2, 1)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&lengths)
            .region_lengths  = view(&regions)
        )!
    ]
    match [locate_in_profile(&profile, .point = (0.0, 0.0, 0.0))!] {
        ..inside found { [testing.expect(found.region == 1)!] }
        ..outside { [testing.fail()!] }
        ..boundary _ { [testing.fail()!] }
    }
    match [locate_in_profile(&profile, .point = (0.75, 0.0, 0.0))!] {
        ..outside {}
        ..inside _ { [testing.fail()!] }
        ..boundary _ { [testing.fail()!] }
    }
    match [locate_in_profile(&profile, .point = (0.25, 0.0, 0.0))!] {
        ..boundary found {
            testing.expect(found.region == 1 and found.contour == 2)!
        }
        ..inside _ { [testing.fail()!] }
        ..outside { [testing.fail()!] }
    }
}

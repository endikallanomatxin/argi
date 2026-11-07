test extrusion_contour_walls_partition_source_spans_and_repeat := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [11]g.Point#(Float64) = (
        (-3.0, -2.0, 0.0),
        (3.0, -2.0, 0.0),
        (3.0, 2.0, 0.0),
        (-3.0, 2.0, 0.0),
        (-1.0, -1.0, 0.0),
        (1.0, -1.0, 0.0),
        (1.0, 1.0, 0.0),
        (-1.0, 1.0, 0.0),
        (5.0, 0.0, 0.0),
        (6.0, 0.0, 0.0),
        (5.0, 1.0, 0.0)
    )
    lengths: [3]UIntNative = (4, 4, 3)
    regions: [2]UIntNative = (2, 1)
    profile ::= [
        planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&lengths)
            .region_lengths  = view(&regions)
        )!
    ]
    extrusion ::= [
        extrude_with_history(.profile = &profile, .displacement = (0.25, 0.0, -2.0))!
    ]
    contour :: UIntNative = 0
    first :: UIntNative = 0
    while contour < 3 {
        walls ::= extrusion_contour_walls(&extrusion, .contour = contour)!
        repeat :: UIntNative = 0
        while repeat < 2 {
            visited :: UIntNative = 0
            for wall in walls {
                expected ::= extrusion_wall(&extrusion, .span = first + visited)!
                testing.expect(wall == expected)!
                [
                    testing.expect(
                        [[t.face_info(&extrusion.model, .face = wall)!].loop_count == 1]
                    )!
                ]
                visited = visited + 1
            }
            testing.expect(visited == lengths[contour])!
            repeat = repeat + 1
        }
        first = first + lengths[contour]
        contour = contour + 1
    }
    testing.expect(first == 11)!
    [
        testing.expect_error(
            .actual_result   = extrusion_contour_walls(&extrusion, .contour = 3)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result = extrusion_contour_walls(
                &extrusion, .contour = integer_limits(.value = contour).maximum
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
}

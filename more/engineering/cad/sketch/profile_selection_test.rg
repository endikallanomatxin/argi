test sketch_explicit_selection_ignores_other_contours_and_tracks_caller_order := (
    .system : System
) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)(.plane = ..yz)!
    first ::= [builder | rectangle($&_, .center = (-2.0, 0.0), .width = 1.0, .height = 1.0)!]
    ignored ::= builder | circle($&_, .center = (20.0, 0.0), .diameter = 2.0)!
    second ::= builder | circle($&_, .center = (2.0, 0.0), .diameter = 0.5)!
    exterior ::= builder | rectangle($&_, .width = 8.0, .height = 6.0)!
    drawing ::= builder | finish_sketch(~_)!
    chosen: [3]ContourRef = (exterior, second, first)
    selection ::= profile_from_contours_with_history(&drawing, .contours = view(&chosen))!
    publication ::= m.profile_brep_with_history(&selection.profile)!
    testing.expect(t.entity_counts(&publication.model).loops == 3)!
    [
        testing.expect([[profile_contour_image(&selection, .contour = exterior)!].contour == 0])!
    ]
    [
        testing.expect([[profile_contour_image(&selection, .contour = second)!].contour == 1])!
    ]
    first_image ::= profile_contour_image(&selection, .contour = first)!
    [
        testing.expect(
            [first_image.contour == 2 and first_image.first_span == 5 and first_image.reversed]
        )!
    ]
    [
        testing.expect(
            [[profile_span_image(&selection, .contour = first, .span = 0)!].span == 8]
        )!
    ]
    for reference in chosen {
        image ::= profile_contour_image(&selection, .contour = reference)!
        source ::= contour_spans(&drawing, .contour = reference)!
        i :: UIntNative = 0
        while i < image.span_count {
            mapped ::= profile_span_image(&selection, .contour = reference, .span = i)!
            use ::= m.published_profile_halfedge(&publication, .span = mapped.span)!
            parameter :: Float64 = 0.0
            while parameter <= 1.0 {
                target ::= parameter
                if mapped.reversed { target = 1.0 - target }
                expected ::= _selection_world_sample(
                    .span      = [get(&source, .index = i)!]
                    .frame     = m.profile_frame(&selection.profile).frame
                    .parameter = parameter
                ).point
                actual ::= [
                    t.halfedge_point(&publication.model, .halfedge = use, .parameter = target)!
                ]
                [
                    testing.expect(
                        [
                            g.norm(g.between(.from = expected, .to = actual).result).value
                            < 0.000001
                        ]
                    )!
                ]
                parameter = parameter + 0.25
            }
            i = i + 1
        }
    }
    [
        testing.expect_error(
            .actual_result   = profile_contour_image(&selection, .contour = ignored)
            .expected_reason = ..not_selected
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = profile_span_image(&selection, .contour = ignored, .span = 0)
            .expected_reason = ..not_selected
        )!
    ]
    -- A second operation can use only the outer contour from the same drawing.
    only_outer: [1]ContourRef = (exterior)
    plain ::= profile_from_contours(&drawing, .contours = view(&only_outer))!
    model ::= m.extrude(.profile = &plain, .displacement = (2.0, 0.0, 0.0))!
    testing.expect(t.is_closed(&model).ok and t.entity_counts(&model).faces == 6)!
    testing.expect(contour_count(&drawing).count == 4)!
}

test sketch_explicit_selection_rejects_invalid_inputs_and_keeps_drawing_reusable := (
    .system : System
) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float32)()!
    exterior ::= builder | rectangle($&_, .width = 4.0, .height = 3.0)!
    hole ::= builder | circle($&_, .diameter = 1.0)!
    drawing ::= builder | finish_sketch(~_)!
    empty: [0]ContourRef = ()
    [
        testing.expect_error(
            .actual_result   = profile_from_contours(&drawing, .contours = view(&empty))
            .expected_reason = ..invalid_region_lengths
        )!
    ]
    [
        testing.expect_error(
            .actual_result = profile_from_contours_with_history(
                &drawing, .contours = view(&empty)
            )
            .expected_reason = ..invalid_region_lengths
        )!
    ]
    repeated: [3]ContourRef = (exterior, hole, hole)
    [
        testing.expect_error(
            .actual_result   = profile_from_contours(&drawing, .contours = view(&repeated))
            .expected_reason = ..intersecting_contours
        )!
    ]
    other ::= SketchBuilder#(.Scalar: Float32)()!
    foreign ::= other | circle($&_, .diameter = 1.0)!
    other_drawing ::= other | finish_sketch(~_)!
    mixed: [2]ContourRef = (exterior, foreign)
    [
        testing.expect_error(
            .actual_result   = profile_from_contours(&drawing, .contours = view(&mixed))
            .expected_reason = ..wrong_domain
        )!
    ]
    [
        testing.expect_error(
            .actual_result = profile_from_contours_with_history(
                &drawing, .contours = view(&mixed)
            )
            .expected_reason = ..wrong_domain
        )!
    ]
    valid: [2]ContourRef = (exterior, hole)
    selection ::= profile_from_contours_with_history(&drawing, .contours = view(&valid))!
    plain ::= profile_from_contours(&drawing, .contours = view(&valid))!
    [
        testing.expect(
            [
                Indexable#(
                    ArrayView#(g.ContourSpan#(Float32))
                ).length(m.profile_spans(&plain).spans | &_).count
                == 5
            ]
        )!
    ]
    [
        testing.expect(
            [[profile_span_image(&selection, .contour = hole, .span = 0)!].span == 4]
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = profile_contour_image(&selection, .contour = foreign)
            .expected_reason = ..wrong_domain
        )!
    ]
    testing.expect(contour_count(&other_drawing).count == 1)!
}

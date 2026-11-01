_selection_world_sample := #(.Scalar: Type: Float) (
    .span: g.ContourSpan#(Scalar), .frame: g.Frame#(Scalar), .parameter: Scalar
) -> (.point: g.Point#(Scalar)) {
    x ::= [1.0 - parameter] * span.start.x + parameter * span.end.x
    y ::= [1.0 - parameter] * span.start.y + parameter * span.end.y
    if span.sweep != 0.0 {
        angle ::= span.sweep * parameter
        dx ::= span.start.x - span.center.x
        dy ::= span.start.y - span.center.y
        x = span.center.x + dx * cos(angle).result - dy * sin(angle).result
        y = span.center.y + dx * sin(angle).result + dy * cos(angle).result
    }
    point = (
        .x = frame.origin.x + frame.x.x * x + frame.y.x * y
        .y = frame.origin.y + frame.x.y * x + frame.y.y * y
        .z = frame.origin.z + frame.x.z * x + frame.y.z * y
    )
}

test sketch_profile_history_composes_through_reordered_and_reversed_contours := (
    .system : System
) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)(.plane = ..xz)!
    first ::= [builder | rectangle($&_, .center = (-2.0, 0.0), .width = 1.0, .height = 1.0)!]
    exterior ::= builder | rectangle($&_, .width = 8.0, .height = 6.0)!
    last ::= builder | circle($&_, .center = (2.0, 0.0), .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    selection ::= profile_with_history(&drawing, .exterior = exterior)!
    publication ::= m.profile_brep_with_history(&selection.profile)!
    references: [3]ContourRef = (first, exterior, last)
    expected_contours: [3]UIntNative = (1, 0, 2)
    first_spans: [3]UIntNative = (4, 0, 8)
    source_index :: UIntNative = 0
    for reference in references {
        image ::= profile_contour_image(&selection, .contour = reference)!
        testing.expect(image.contour == expected_contours[source_index])!
        testing.expect(image.first_span == first_spans[source_index])!
        testing.expect(image.reversed == [source_index != 1])!
        loop ::= m.published_profile_loop(&publication, .contour = image.contour)!
        source ::= contour_spans(&drawing, .contour = reference)!
        [
            testing.expect(
                [
                    image.span_count
                    == Indexable#(ArrayView#(g.ContourSpan#(Float64))).length(&source).count
                ]
            )!
        ]
        i :: UIntNative = 0
        while i < image.span_count {
            span_image ::= profile_span_image(&selection, .contour = reference, .span = i)!
            use ::= m.published_profile_halfedge(&publication, .span = span_image.span)!
            [
                testing.expect(
                    [[t.halfedge_info(&publication.model, .halfedge = use)!].loop == loop]
                )!
            ]
            parameter :: Float64 = 0.0
            while parameter <= 1.0 {
                target ::= parameter
                if span_image.reversed { target = 1.0 - target }
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
        [
            testing.expect_error(
                .actual_result = profile_span_image(
                    &selection, .contour = reference, .span = image.span_count
                )
                .expected_reason = ..out_of_bounds
            )!
        ]
        source_index = source_index + 1
    }
}

test sketch_profile_history_rejects_other_drawing_and_preserves_plain_selection := (
    .system : System
) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float32)()!
    exterior ::= builder | rectangle($&_, .width = 4.0, .height = 3.0)!
    hole ::= builder | circle($&_, .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    selection ::= profile_with_history(&drawing, .exterior = exterior)!
    plain ::= profile(&drawing, .exterior = exterior)!
    a ::= m.profile_spans(&selection.profile).spans
    b ::= m.profile_spans(&plain).spans
    i :: UIntNative = 0
    while i < 5 {
        left ::= get(&a, .index = i)!
        right ::= get(&b, .index = i)!
        [
            testing.expect(
                [
                    left.start.x == right.start.x
                    and left.end.y == right.end.y
                    and left.sweep == right.sweep
                ]
            )!
        ]
        i = i + 1
    }
    other ::= SketchBuilder#(.Scalar: Float32)()!
    foreign ::= other | rectangle($&_, .width = 4.0, .height = 3.0)!
    other_drawing ::= other | finish_sketch(~_)!
    [
        testing.expect_error(
            .actual_result   = profile_contour_image(&selection, .contour = foreign)
            .expected_reason = ..wrong_domain
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = profile_span_image(&selection, .contour = foreign, .span = 0)
            .expected_reason = ..wrong_domain
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = profile_with_history(&drawing, .exterior = foreign)
            .expected_reason = ..wrong_domain
        )!
    ]
    second ::= profile_with_history(&drawing, .exterior = exterior)!
    [
        testing.expect([profile_contour_image(&second, .contour = hole)!].reversed)!
    ]
    [
        testing.expect([[profile_span_image(&second, .contour = hole, .span = 0)!].span == 4])!
    ]
    testing.expect(contour_count(&other_drawing).count == 1)!
}

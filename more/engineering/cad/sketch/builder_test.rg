test sketch_builder_pipe_references_survive_growth_and_publication := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    builder ::= SketchBuilder#(.Scalar: Float64)()!
    outer ::= builder | rectangle($&_, .width = 8.0, .height = 6.0)!
    builder | circle($&_, .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    testing.expect(contour_count(&drawing).count == 2)!
    spans ::= drawing | contour_spans(&_, .contour = outer)!
    testing.expect(Indexable#(ArrayView#(g.ContourSpan#(Float64))).length(&spans).count == 4)!
    testing.expect([get(&spans, .index = 0)!].start.x == -4.0)!
}

test sketch_builder_rejects_invalid_shape_without_appending := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    builder ::= SketchBuilder#(.Scalar: Float32)()!
    [
        testing.expect_error(
            .actual_result   = [builder | circle($&_, .diameter = -1.0)]
            .expected_reason = ..invalid_surface
        )!
    ]
    outer ::= builder | rectangle($&_, .width = 4.0, .height = 3.0)!
    drawing ::= builder | finish_sketch(~_)!
    testing.expect(contour_count(&drawing).count == 1)!
    other ::= SketchBuilder#(.Scalar: Float32)()!
    other | circle($&_, .diameter = 1.0)!
    foreign ::= other | finish_sketch(~_)!
    [
        testing.expect_error(
            .actual_result   = contour_spans(&foreign, .contour = outer)
            .expected_reason = ..wrong_domain
        )!
    ]
}

test sketch_builder_init_uses_allocator_assumption := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    builder: SketchBuilder#(Float64) = [SketchBuilder#(Float64)()!]
    builder | rectangle($&_, .width = 2.0, .height = 1.0)!
    drawing ::= builder | finish_sketch(~_)!
    testing.expect(contour_count(&drawing).count == 1)!
}

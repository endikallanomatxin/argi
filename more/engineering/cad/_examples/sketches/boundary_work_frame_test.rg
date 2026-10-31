-- Follow a retained opening reference to its analytic boundary. The directed
-- derivative and face normal define an oriented work frame at a boundary point.
-- This is a geometric placement, not an attached feature or a boolean operation.
test usage_work_frame_from_analytic_boundary := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    sketch ::= s.SketchBuilder#(.Scalar: Float64)()!
    outline ::= sketch | s.rectangle($&_, .width = 4.0, .height = 3.0)!
    opening ::= sketch | s.circle($&_, .diameter = 1.0)!
    drawing ::= sketch | s.finish_sketch(~_)!
    selection ::= s.profile_with_history(&drawing, .exterior = outline)!
    publication ::= m.profile_brep_with_history(&selection.profile)!
    image ::= s.profile_span_image(&selection, .contour = opening, .span = 0)!
    use ::= m.published_profile_halfedge(&publication, .span = image.span)!
    face ::= m.published_profile_face(&publication, .region = 0)!

    parameter: Float64 = 0.25
    position ::= t.halfedge_point(&publication.model, .halfedge = use, .parameter = parameter)!
    velocity ::= [
        t.halfedge_derivative(&publication.model, .halfedge = use, .parameter = parameter)!
    ]
    uv ::= t.halfedge_parameters(&publication.model, .halfedge = use, .parameter = parameter)!
    normal ::= t.face_normal(&publication.model, .face = face, .u = uv.u, .v = uv.v)!
    frame ::= [
        g.frame_from_directions(.origin = position, .normal = normal, .x_direction = velocity)!
    ]

    marker_sketch ::= s.sketch_builder_on_frame(.frame = frame)!
    marker_outline ::= [marker_sketch | s.rectangle($&_, .width = 0.5, .height = 0.25)!]
    marker_drawing ::= marker_sketch | s.finish_sketch(~_)!
    marker_section ::= s.profile(&marker_drawing, .exterior = marker_outline)!
    marker ::= m.profile_brep(&marker_section)!
    testing.expect(t.entity_counts(&marker).faces == 1)!
    -- The derivative retains the full normalized-circle speed, not unit length.
    speed ::= g.norm(velocity).value
    testing.expect(speed > 3.14159 and speed < 3.14160)!
    testing.expect(g.dot(.left = frame.x, .right = velocity).value / speed > 0.999999)!
    testing.expect(g.dot(.left = frame.z, .right = normal).value > 0.999999)!
    testing.expect(g.norm(g.between(.from = frame.origin, .to = position).result).value == 0.0)!
}

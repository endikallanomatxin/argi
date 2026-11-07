-- Use the generated end cap as the support for another sketch. These are two
-- separate closed models: placement does not imply a boolean union or attachment.
test usage_sketch_on_generated_cap := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    base_frame ::= [
        g.frame_from_directions#(Float64)(
            .origin      = (0.0, 0.0, 0.0)
            .normal      = (0.6, 0.0, 0.8)
            .x_direction = (0.8, 0.0, -0.6)
        )!
    ]
    sketch ::= s.sketch_builder_on_frame(.frame = base_frame)!
    outline ::= sketch | s.rectangle($&_, .width = 6.0, .height = 4.0)!
    drawing ::= sketch | s.finish_sketch(~_)!
    section ::= s.profile(&drawing, .exterior = outline)!
    displacement: g.Displacement#(Float64) = (1.2, 0.0, 1.6)
    base ::= m.extrude_with_history(.profile = &section, .displacement = displacement)!

    caps ::= m.extrusion_caps(&base, .region = 0)!
    support ::= t.face_plane(&base.model, .face = caps.end)!
    -- Choose the displaced sketch origin, rather than the cap's first vertex.
    anchor: g.Point#(Float64) = (displacement.x, displacement.y, displacement.z)
    origin ::= g.project_on_plane(.point = anchor, .plane = support)!
    work_frame ::= [
        g.frame_from_directions(
            .origin = origin, .normal = support.normal, .x_direction = base_frame.x
        )!
    ]
    next_sketch ::= s.sketch_builder_on_frame(.frame = work_frame)!
    boss_outline ::= next_sketch | s.rectangle($&_, .width = 2.0, .height = 1.0)!
    next_drawing ::= next_sketch | s.finish_sketch(~_)!
    boss_section ::= s.profile(&next_drawing, .exterior = boss_outline)!
    boss ::= [
        m.extrude_with_history(
            .profile      = &boss_section
            .displacement = (work_frame.z.x, work_frame.z.y, work_frame.z.z)
        )!
    ]
    testing.expect(t.is_closed(&base.model).ok and t.is_closed(&boss.model).ok)!
    testing.expect(g.dot(.left = work_frame.x, .right = base_frame.x).value > 0.999999)!
    [
        testing.expect(
            [g.norm(g.between(.from = anchor, .to = work_frame.origin).result).value < 0.000001]
        )!
    ]
    boss_caps ::= m.extrusion_caps(&boss, .region = 0)!
    bottom ::= t.face_plane(&boss.model, .face = boss_caps.start)!
    testing.expect(g.dot(.left = bottom.normal, .right = support.normal).value < -0.999999)!
    corner ::= m.profile_point(&boss_section, .index = 0)!
    offset ::= g.between(.from = support.origin, .to = corner).result
    distance ::= g.dot(.left = support.normal, .right = offset).value
    testing.expect(distance > -0.000001 and distance < 0.000001)!
}

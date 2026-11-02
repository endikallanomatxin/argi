-- A rectangular spacer with a rectangular clearance opening. The same selected
-- profile can be published as a planar face or extruded into a closed model.
test usage_sketch_spacer_extrusion := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    sketch ::= s.SketchBuilder#(.Scalar: Float64)()!
    outline ::= sketch | s.rectangle($&_, .width = 8.0, .height = 6.0)!
    opening ::= sketch | s.rectangle($&_, .width = 2.0, .height = 2.0)!
    -- This independent contour remains available for a later operation.
    [sketch | s.rectangle($&_, .center = (12.0, 0.0), .width = 1.0, .height = 1.0)!]
    drawing ::= sketch | s.finish_sketch(~_)!
    chosen: [2]s.ContourRef = (outline, opening)
    selection ::= s.profile_from_contours_with_history(&drawing, .contours = view(&chosen))!
    extrusion ::= [
        m.extrude_with_history(.profile = &selection.profile, .displacement = (0.25, 0.0, 2.0))!
    ]
    testing.expect(t.is_closed(&extrusion.model).ok)!
    counts ::= t.entity_counts(&extrusion.model)
    testing.expect(counts.vertices == 16 and counts.edges == 24 and counts.faces == 10)!
    -- Follow the opening's reference to its four generated walls.
    image ::= s.profile_contour_image(&selection, .contour = opening)!
    visited :: UIntNative = 0
    for wall in [m.extrusion_contour_walls(&extrusion, .contour = image.contour)!] {
        [
            testing.expect([[t.face_info(&extrusion.model, .face = wall)!].loop_count == 1])!
        ]
        visited = visited + 1
    }
    testing.expect(visited == 4)!
    caps ::= m.extrusion_caps(&extrusion, .region = 0)!
    [
        testing.expect([[t.face_info(&extrusion.model, .face = caps.end)!].loop_count == 2])!
    ]

    -- The center is in the clearance opening, not in the material profile.
    match [m.locate_in_profile(&selection.profile, .point = (0.0, 0.0, 0.0))!] {
        ..outside {}
        ..inside _ { [testing.fail()!] }
        ..boundary _ {
            testing.fail()!
        }
    }
}

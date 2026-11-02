-- Declare a spacer cross-section once and reuse its dimensions and opening
-- on two work frames. Each extrusion owns a separate closed model.
test usage_reuse_profile_on_work_frames := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    sketch ::= s.SketchBuilder#(.Scalar: Float64)()!
    outline ::= sketch | s.rectangle($&_, .width = 4.0, .height = 3.0)!
    opening ::= sketch | s.rectangle($&_, .width = 1.0, .height = 1.0)!
    drawing ::= sketch | s.finish_sketch(~_)!
    selection ::= s.profile_with_history(&drawing, .exterior = outline)!
    opening_image ::= s.profile_contour_image(&selection, .contour = opening)!

    first ::= [
        g.frame_from_directions#(Float64)(
            .origin = (0.0, 0.0, 2.0), .normal = (0.0, 0.0, 1.0), .x_direction = (1.0, 0.0, 0.0)
        )!
    ]
    second ::= [
        g.frame_from_directions#(Float64)(
            .origin = (5.0, 0.0, 0.0), .normal = (1.0, 0.0, 0.0), .x_direction = (0.0, 1.0, 0.0)
        )!
    ]
    placements: [2]g.Frame#(Float64) = (first, second)
    for frame in placements {
        section ::= m.profile_on_frame(&selection.profile, .frame = frame)!
        extrusion ::= [
            m.extrude_with_history(
                .profile = &section, .displacement = (frame.z.x, frame.z.y, frame.z.z)
            )!
        ]
        testing.expect(t.is_closed(&extrusion.model).ok)!
        -- Placement preserves profile positions, so the original selection's
        -- opening image still identifies the generated opening walls.
        count :: UIntNative = 0
        for wall in [m.extrusion_contour_walls(&extrusion, .contour = opening_image.contour)!] {
            [
                testing.expect([[t.face_info(&extrusion.model, .face = wall)!].loop_count == 1])!
            ]
            count = count + 1
        }
        testing.expect(count == 4)!
        match [m.locate_in_profile(&section, .point = frame.origin)!] {
            ..outside {}
            ..inside _ {
                testing.fail()!
            }
            ..boundary _ {
                testing.fail()!
            }
        }
        caps ::= m.extrusion_caps(&extrusion, .region = 0)!
        [
            testing.expect(
                [
                    g.dot(
                        .left  = [t.face_plane(&extrusion.model, .face = caps.end)!].normal
                        .right = frame.z
                    ).value
                    > 0.999999
                ]
            )!
        ]
    }
    -- The source remains at its original world placement.
    testing.expect(m.profile_frame(&selection.profile).frame.origin.z == 0.0)!
}

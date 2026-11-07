-- Check semantic references after rebuilding with different dimensions and
-- declaration numbering. No source ID is compared across drawing domains.
test sketch_extrusion_history_follows_opening_after_rebuild_and_renumbering := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    variants: [2]Bool = (false, true)
    for shifted in variants {
        builder ::= SketchBuilder#(.Scalar: Float64)(.plane = ..yz)!
        opening_width :: Float64 = 1.0
        height :: Float64 = 2.0
        if shifted {
            builder | rectangle($&_, .center = (12.0, 0.0), .width = 1.0, .height = 1.0)!
            opening_width = 2.0
            height = -2.0
        }
        outline ::= builder | rectangle($&_, .width = 8.0, .height = 6.0)!
        opening ::= builder | rectangle($&_, .width = opening_width, .height = 2.0)!
        if shifted == false {
            builder | rectangle($&_, .center = (12.0, 0.0), .width = 1.0, .height = 1.0)!
        }
        drawing ::= builder | finish_sketch(~_)!
        chosen: [2]ContourRef = (outline, opening)
        selection ::= profile_from_contours_with_history(&drawing, .contours = view(&chosen))!
        displacement: g.Displacement#(Float64) = (height, 0.25, 0.5)
        extrusion ::= [
            m.extrude_with_history(.profile = &selection.profile, .displacement = displacement)!
        ]
        image ::= profile_contour_image(&selection, .contour = opening)!
        source ::= contour_spans(&drawing, .contour = opening)!
        frame ::= m.profile_frame(&selection.profile).frame
        count :: UIntNative = 0
        for wall in [m.extrusion_contour_walls(&extrusion, .contour = image.contour)!] {
            plane ::= t.face_plane(&extrusion.model, .face = wall)!
            testing.expect(plane.normal.y != 0.0 or plane.normal.z != 0.0)!
            count = count + 1
        }
        testing.expect(count == 4)!
        span :: UIntNative = 0
        while span < 4 {
            mapped ::= profile_span_image(&selection, .contour = opening, .span = span)!
            wall ::= m.extrusion_wall(&extrusion, .span = mapped.span)!
            plane ::= t.face_plane(&extrusion.model, .face = wall)!
            source_span ::= get(&source, .index = span)!
            a ::= _selection_world_sample(
                .span = source_span, .frame = frame, .parameter = 0.0
            ).point
            b ::= _selection_world_sample(
                .span = source_span, .frame = frame, .parameter = 1.0
            ).point
            translated: g.Point#(Float64) = (
                .x = a.x + displacement.x
                .y = [a.y + displacement.y]
                .z = [a.z + displacement.z]
            )
            samples: [3]g.Point#(Float64) = (a, b, translated)
            for sample in samples {
                distance ::= g.dot(
                    .left  = plane.normal
                    .right = g.between(.from = plane.origin, .to = sample).result
                ).value
                testing.expect(distance > -0.000001 and distance < 0.000001)!
            }
            -- Source sketch holes are CCW; selection reverses them, so their
            -- generated wall normal opposes source tangent cross displacement.
            cross ::= g.cross(
                .left = g.between(.from = a, .to = b).result, .right = displacement
            ).result
            testing.expect(g.dot(.left = plane.normal, .right = cross).value * height < 0.0)!
            span = span + 1
        }
        caps ::= m.extrusion_caps(&extrusion, .region = 0)!
        start_normal ::= t.face_plane(&extrusion.model, .face = caps.start)!.normal
        testing.expect(start_normal.x * height < 0.0)!
        end_normal ::= t.face_plane(&extrusion.model, .face = caps.end)!.normal
        testing.expect(end_normal.x * height > 0.0)!
        testing.expect(t.is_closed(&extrusion.model).ok)!
    }
}

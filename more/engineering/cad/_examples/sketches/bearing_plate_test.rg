-- Sketch a bearing mounting plate, centered on the shaft axis:
--      +-----------------------------------+
--      |    o           O           o      |
--      +-----------------------------------+
--        mounting     shaft     mounting
-- Dimensions use one consistent model unit. This produces an analytic planar profile;
-- curved extrusion is not implemented yet.
test usage_sketch_bearing_plate := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    width: Float64 = 80.0
    height: Float64 = 40.0
    corner_radius: Float64 = 4.0
    shaft_diameter: Float64 = 20.0
    mounting_diameter: Float64 = 5.0
    mounting_spacing: Float64 = 60.0

    sketch ::= s.SketchBuilder#(.Scalar: Float64)(.plane = ..xy)!

    outline ::= [
        [
            sketch
            | s.rounded_rectangle(
                $&_, .width = width, .height = height, .radius = corner_radius
            )!
        ]
    ]

    -- Retain this reference to find the opening again in the published model.
    shaft ::= sketch | s.circle($&_, .diameter = shaft_diameter)!

    -- Both mounting holes depend on the same spacing, so they remain symmetric.
    half_spacing ::= mounting_spacing / 2.0
    left_x ::= 0.0 - half_spacing
    mounting_x: [2]Float64 = (left_x, half_spacing)
    for x in mounting_x {
        [sketch | s.circle($&_, .center = (x, 0.0), .diameter = mounting_diameter)!]
    }

    drawing ::= sketch | s.finish_sketch(~_)!
    -- Select the exterior once; all remaining contours become holes.
    selection ::= s.profile_with_history(&drawing, .exterior = outline)!
    publication ::= m.profile_brep_with_history(&selection.profile)!
    testing.expect(t.entity_counts(&publication.model).faces == 1)!
    testing.expect(t.entity_counts(&publication.model).loops == 4)!
    -- Follow the shaft reference through profile selection and publication.
    shaft_image ::= s.profile_contour_image(&selection, .contour = shaft)!
    shaft_loop ::= m.published_profile_loop(&publication, .contour = shaft_image.contour)!
    [
        testing.expect([[t.loop_info(&publication.model, .loop = shaft_loop)!].count == 1])!
    ]
}

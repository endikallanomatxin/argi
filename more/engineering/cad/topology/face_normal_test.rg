test model_face_normals_follow_orientation_without_changing_region := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    model ::= _partitioned_oblique_cylinder#(.Scalar: Float64)(.allocator = allocator)!
    inverse ::= reverse_orientation(&model)!
    i :: UIntNative = 0
    while i < 3 {
        face ::= i | convert#(.to: FaceId)(_)
        n ::= face_normal(&model, .face = face, .u = 0.3, .v = 0.4)!
        r ::= face_normal(&inverse, .face = face, .u = 0.3, .v = 0.4)!
        testing.expect(n.x == [0.0 - r.x] and n.y == [0.0 - r.y] and n.z == [0.0 - r.z])!
        support ::= face_surface(&model, .face = face)!
        original ::= g.surface_normal(.surface = support, .u = 0.3, .v = 0.4)!
        sign :: Float64 = 1.0
        if [face_info(&model, .face = face)!].reversed { sign = -1.0 }
        testing.expect(g.dot(.left = n, .right = original).value * sign > 0.999)!
        [
            testing.expect(
                [
                    [face_contains_parameters(&model, .face = face, .u = 0.3, .v = 0.4)!]
                    == [face_contains_parameters(&inverse, .face = face, .u = 0.3, .v = 0.4)!]
                ]
            )!
        ]
        i = i + 1
    }
    bottom ::= face_normal(&model, .face = (.value = 1), .u = 0.0, .v = 0.0)!
    top ::= face_normal(&model, .face = (.value = 2), .u = 0.0, .v = 0.0)!
    testing.expect(bottom.z == -1.0 and top.z > 0.0 and top.x < 0.0)!
    [
        testing.expect_error(
            .actual_result   = face_normal(&model, .face = (.value = 3), .u = 0.0, .v = 0.0)
            .expected_reason = ..out_of_bounds
        )!
    ]
}

test model_face_normal_at_sphere_pole_and_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    model ::= _brep_hemisphere#(.Scalar: Float32)(.allocator = allocator)!
    reversed ::= reverse_orientation(&model)!
    normal ::= face_normal(&model, .face = (.value = 0), .u = 13.0, .v = 1.5707963267948966)!
    inverse ::= [
        face_normal(&reversed, .face = (.value = 0), .u = -7.0, .v = 1.5707963267948966)!
    ]
    testing.expect(normal.z == [0.0 - inverse.z])!
    testing.expect(g.norm(normal).value > 0.999)!
    [
        testing.expect_error(
            .actual_result   = face_normal(&model, .face = (.value = 0), .u = 0.0, .v = 1.6)
            .expected_reason = ..out_of_bounds
        )!
    ]
}

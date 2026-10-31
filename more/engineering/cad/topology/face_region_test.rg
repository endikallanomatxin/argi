test model_face_region_respects_support_domain := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    model ::= _brep_hemisphere#(.Scalar: Float64)(.allocator = allocator)!
    support ::= face_surface(&model, .face = (.value = 0))!
    [
        testing.expect(
            [
                g.validate_surface_parameters(
                    .surface = support, .u = 8.0, .v = 1.5707963267948966
                )!
            ]
        )!
    ]
    [
        testing.expect(
            [
                face_contains_parameters(
                    &model, .face = (.value = 0), .u = 8.0, .v = 1.5707963267948966
                )!
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    face_contains_parameters(
                        &model, .face = (.value = 0), .u = -8.0, .v = -1.5707963267948966
                    )!
                ]
                == false
            ]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = face_contains_parameters(
                &model, .face = (.value = 0), .u = 0.0, .v = 1.6
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = g.surface_point(.surface = support, .u = 0.0, .v = 1.6)
            .expected_reason = ..out_of_bounds
        )!
    ]
    testing.expect(entity_counts(&model).vertices == 0 and entity_counts(&model).edges == 1)!
}

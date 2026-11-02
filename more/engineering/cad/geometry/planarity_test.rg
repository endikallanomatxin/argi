test geometry_planarity_invariant_under_point_order := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [5]Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0000009),
        (0.0, 100.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    expected ::= _infer_region_plane(.points = view(&points), .tolerance = 0.000001)!
    shift :: UIntNative = 0
    while shift < 5 {
        permuted :: [5]Point#(Float64) = points
        i :: UIntNative = 0
        while i < 5 {
            permuted[i] = points[[i + shift] % 5]
            i = i + 1
        }
        actual ::= _infer_region_plane(.points = view(&permuted), .tolerance = 0.000001)!
        [
            testing.expect(
                [
                    actual.origin.x == expected.origin.x
                    and actual.origin.y == expected.origin.y
                    and actual.origin.z == expected.origin.z
                ]
            )!
        ]
        [
            testing.expect(
                [
                    actual.normal.x == expected.normal.x
                    and actual.normal.y == expected.normal.y
                    and actual.normal.z == expected.normal.z
                ]
            )!
        ]
        shift = shift + 1
    }
}

test geometry_planarity_rejection_independent_of_start := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [4]Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.1),
        (0.0, 2.0, 0.0)
    )
    lengths: [1]UIntNative = (4)
    regions: [1]UIntNative = (1)
    shift :: UIntNative = 0
    while shift < 4 {
        permuted :: [4]Point#(Float64) = points
        i :: UIntNative = 0
        while i < 4 {
            permuted[i] = points[[shift + 4 - i] % 4]
            i = i + 1
        }
        [
            testing.expect_error(
                .expected_reason = ..nonplanar_face
                .actual_result   = planar_regions_plane(
                    .points          = view(&permuted)
                    .contour_lengths = view(&lengths)
                    .region_lengths  = view(&regions)
                )
            )!
        ]
        shift = shift + 1
    }
}

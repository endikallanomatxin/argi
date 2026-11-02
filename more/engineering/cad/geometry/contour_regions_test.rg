_ContourRegionTestErrors := choice_union#(.a: GeometryErrors, .b: (..test_failed))

_mixed_chart_spans := #(.Scalar: Type: Float) (.radius: Scalar) -> (
    .spans : [3]ContourSpan#(Scalar)
) {
    spans = (
        (.start = (0.0, 0.0), .end = (radius, 0.0)),
        (
            .start  = (radius, 0.0)
            .end    = (0.0 - radius, 0.0)
            .center = (0.0, 0.0)
            .sweep  = 3.141592653589793
        ),
        (.start = (0.0 - radius, 0.0), .end = (0.0, 0.0))
    )
}

test geometry_mixed_contour_classification := (.system: System) -> !() {
    spans ::= _mixed_chart_spans#(Float64)(.radius = 3.0).spans
    lengths: [1]UIntNative = (3,)
    [validate_contour_region(.spans = view(&spans), .lengths = view(&lengths))!]
    match [locate_in_contour_spans(.spans = view(&spans), .point = (0.0, 1.0))!] {
        ..inside {}
        ..outside { [testing.fail()!] }
        ..boundary {
            testing.fail()!
        }
    }
    match [locate_in_contour_spans(.spans = view(&spans), .point = (0.0, -1.0))!] {
        ..outside {}
        ..inside { [testing.fail()!] }
        ..boundary {
            testing.fail()!
        }
    }
    match [locate_in_contour_spans(.spans = view(&spans), .point = (0.0, 3.0))!] {
        ..boundary {}
        ..inside { [testing.fail()!] }
        ..outside { [testing.fail()!] }
    }
}

test geometry_mixed_contour_rejects_crossings_overlap_and_bad_orientation := (.system: System) -> !() {
    crossing: [4]ContourSpan#(Float64) = (
        (.start = (-2.0, -1.0), .end = (2.0, 1.0)),
        (.start = (2.0, 1.0), .end = (-2.0, 1.0)),
        (.start = (-2.0, 1.0), .end = (2.0, -1.0)),
        (.start = (2.0, -1.0), .end = (-2.0, -1.0))
    )
    four: [1]UIntNative = (4,)
    [
        testing.expect_error(
            .actual_result = validate_contour_region(
                .spans = view(&crossing), .lengths = view(&four)
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    overlap: [2]ContourSpan#(Float64) = (
        (.start = (0.0, 0.0), .end = (2.0, 0.0)),
        (.start = (2.0, 0.0), .end = (0.0, 0.0))
    )
    two: [1]UIntNative = (2,)
    [
        testing.expect_error(
            .actual_result = validate_contour_region(
                .spans = view(&overlap), .lengths = view(&two)
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    good ::= _mixed_chart_spans#(Float32)(.radius = 3.0).spans
    three: [1]UIntNative = (3,)
    [validate_contour_region(.spans = view(&good), .lengths = view(&three))!]
    [
        testing.expect_error(
            .actual_result = validate_contour_region(
                .spans = view(&good), .lengths = view(&three), .reversed = true
            )
            .expected_reason = ..inconsistent_orientation
        )!
    ]
}

test geometry_mixed_contour_pair_intersections := (.system: System) -> !() {
    radius: Float64 = 2.0
    outer: ContourSpan#(Float64) = (
        .start  = (radius, 0.0)
        .end    = (radius, 0.0)
        .center = (0.0, 0.0)
        .sweep  = 6.283185307179586
    )
    crossing: ContourSpan#(Float64) = (
        .start  = (3.0, 1.0)
        .end    = (3.0, 1.0)
        .center = (1.0, 1.0)
        .sweep  = -6.283185307179586
    )
    invalid: [2]ContourSpan#(Float64) = (outer, crossing)
    lengths: [2]UIntNative = (1, 1)
    [
        testing.expect_error(
            .actual_result = validate_contour_region(
                .spans = view(&invalid), .lengths = view(&lengths)
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    inner: ContourSpan#(Float64) = (
        .start  = (1.0, 0.0)
        .end    = (1.0, 0.0)
        .center = (0.0, 0.0)
        .sweep  = -6.283185307179586
    )
    valid: [2]ContourSpan#(Float64) = (outer, inner)
    [validate_contour_region(.spans = view(&valid), .lengths = view(&lengths))!]
}

test geometry_mixed_contour_vertex_ray_and_major_arc := (.system: System) -> !() {
    arc: ContourSpan#(Float64) = (
        .start  = (1.0, 0.0)
        .end    = (0.0, -1.0)
        .center = (0.0, 0.0)
        .sweep  = 4.71238898038469
    )
    line: ContourSpan#(Float64) = (.start = (0.0, -1.0), .end = (1.0, 0.0))
    spans: [2]ContourSpan#(Float64) = (arc, line)
    lengths: [1]UIntNative = (2,)
    [validate_contour_region(.spans = view(&spans), .lengths = view(&lengths))!]
    match [locate_in_contour_spans(.spans = view(&spans), .point = (0.0, 0.0))!] {
        ..inside {}
        ..outside { [testing.fail()!] }
        ..boundary { [testing.fail()!] }
    }
    match [locate_in_contour_spans(.spans = view(&spans), .point = (2.0, 0.0))!] {
        ..outside {}
        ..inside { [testing.fail()!] }
        ..boundary { [testing.fail()!] }
    }
}

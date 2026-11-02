test geometry_arc_endpoint_rounding_preserves_ray_parity := (.system: System) -> !() {
    -- The first arc ends just above the next arc's start after evaluation of
    -- cos(pi/2). The downward crossing at x=-2 must still be counted once.
    spans: [4]ContourSpan#(Float64) = (
        (
            .start = (0.0, 2.0)
            .end   = (-2.0, 0.00000000000000012246467991473532)
            .sweep = 1.5707963267948966
        ),
        (
            .start = (-2.0, 0.0)
            .end   = (0.0, -2.0)
            .sweep = 1.5707963267948966
        ),
        (
            .start = (0.0, -2.0)
            .end   = (2.0, 0.0)
            .sweep = 1.5707963267948966
        ),
        (
            .start = (2.0, 0.0)
            .end   = (0.0, 2.0)
            .sweep = 1.5707963267948966
        )
    )
    lengths: [1]UIntNative = (4,)
    [validate_contour_region(.spans = view(&spans), .lengths = view(&lengths))!]
    x :: Float64 = -3.0
    while x <= 3.0 {
        actual ::= locate_in_contour_spans(.spans = view(&spans), .point = (x, 0.0))!
        match actual {
            ..inside { [testing.expect(x > -2.0 and x < 2.0)!] }
            ..outside { [testing.expect(x < -2.0 or x > 2.0)!] }
            ..boundary { [testing.expect(x == -2.0 or x == 2.0)!] }
        }
        x = x + 0.25
    }
}

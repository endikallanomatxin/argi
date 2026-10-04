math := import ("math/linear_algebra")
main(.system: System) -> (.status_code: Int32 = 0) := {
    a: math.Vector#(.n = 3, .t: Float64) = (.values = (1.0, 2.0, 3.0))
    b: math.Vector#(.n = 3, .t: Float64) = (.values = (4.0, 5.0, 6.0))
    expected_dot: Float64 = 32.0
    expected_sum: Float64 = 9.0
    factor: Float64 = 2.0
    expected_product: Float64 = 77.0
    if math.dot(.left = &a, .right = &b).value != expected_dot { abort }
    added ::= math.add(.left = &a, .right = &b)
    if added.values[2] != expected_sum { abort }
    scaled ::= math.scale(.self = &a, .factor = 2.0)
    if scaled.values[0] != factor { abort }
    left: math.Matrix#(.rows = 2, .cols = 3, .t: Int32) = (.values = ((1, 2, 3), (4, 5, 6)))
    right: math.Matrix#(.rows = 3, .cols = 2, .t: Int32) = (.values = ((7, 8), (9, 10), (11, 12)))
    product ::= math.multiply(.left = &left, .right = &right)
    if product.values[0][0] != 58 or product.values[1][1] != 154 { abort }
    transposed ::= math.transpose(.self = &left)
    if transposed.values[2][1] != 6 { abort }
    values: [6]Float64 = (1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
    dynamic ::= unwrap_or_abort(.value = math.DynamicMatrix(.rows = 2, .cols = 3,
            .values = view(.array = &values), .allocator = system.page_allocator)).result
    other ::= unwrap_or_abort(.value = math.transpose(.self = &dynamic,
            .allocator = system.page_allocator)).result
    result ::= unwrap_or_abort(.value = math.multiply(.left = &dynamic, .right = &other,
            .allocator = system.page_allocator)).result
    if unwrap_or_abort(.value = math.get(.self = &result, .row = 1, .col = 1)).result != expected_product {
        abort
    }
    match math.multiply(.left = &dynamic, .right = &dynamic, .allocator = system.page_allocator) {
        ..error _ {} ..ok _ { abort }
    }
    match math.DynamicMatrix(.rows = 2, .cols = 2, .values = view(.array = &values),
        .allocator = system.page_allocator) { ..error _ {} ..ok _ { abort } }
    empty: [0]Float64 = ()
    zeros ::= unwrap_or_abort(.value = math.DynamicMatrix(.rows = 2, .cols = 0,
            .values = view(.array = &empty), .allocator = system.page_allocator)).result
    zero_transpose ::= unwrap_or_abort(.value = math.transpose(.self = &zeros,
            .allocator = system.page_allocator)).result
    zero_product ::= unwrap_or_abort(.value = math.multiply(.left = &zeros, .right = &zero_transpose,

            .allocator = system.page_allocator)).result
    if unwrap_or_abort(.value = math.get(.self = &zero_product, .row = 1, .col = 1)).result != 0.0 {
        abort
    }
    vector ::= unwrap_or_abort(.value = math.DynamicVector(.values = view(.array = &values),
            .allocator = system.page_allocator)).result
    if unwrap_or_abort(.value = math.dot(.left = &vector, .right = &vector)).result != 91.0 {
        abort
    }
    grown ::= unwrap_or_abort(.value = math.add(.left = &vector, .right = &vector,
            .allocator = system.page_allocator)).result
    if unwrap_or_abort(.value = math.get(.self = &grown, .index = 5)).result != 12.0 { abort }
    scaled_vector ::= unwrap_or_abort(.value = math.scale(.self = &vector, .factor = 2.0,
            .allocator = system.page_allocator)).result
    unwrap_or_abort(.value = math.set(.self = $&scaled_vector, .index = 0, .value = factor))
    match math.get(.self = &dynamic, .row = 2, .col = 0) { ..error _ {} ..ok _ { abort } }
    summed ::= unwrap_or_abort(.value = math.add(.left = &dynamic, .right = &dynamic,
            .allocator = system.page_allocator)).result
    if unwrap_or_abort(.value = math.get(.self = &summed, .row = 1, .col = 2)).result != 12.0 {
        abort
    }

    match math.DynamicMatrix(.rows = 18446744073709551615, .cols = 2,
        .values = view(.array = &empty), .allocator = system.page_allocator) {
        ..error _ {} ..ok _ { abort }
    }
    empty_vector ::= unwrap_or_abort(.value = math.DynamicVector(.values = view(.array = &empty),
            .allocator = system.page_allocator)).result
    match math.dot(.left = &vector, .right = &empty_vector) { ..error _ {} ..ok _ { abort } }
    empty_fixed: math.Vector#(.n = 0, .t: Int32) = (.values = ())
    if math.dot(.left = &empty_fixed, .right = &empty_fixed) != 0 { abort }

    refusing :: RefusingAllocator = (.attempts = 0)
    match math.DynamicMatrix(.rows = 3, .cols = 3, .values = view(.array = &values),
        .allocator = $&refusing) { ..error _ {} ..ok _ { abort } }
    if refusing.attempts != 0 { abort }
    match math.multiply(.left = &dynamic, .right = &other, .allocator = $&refusing) {
        ..error item { if item.reason != ..out_of_memory { abort } } ..ok _ { abort }
    }
    if refusing.attempts != 1 { abort }

}

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    a ::= BitSet(.count = 10, .allocator = allocator)!
    b ::= BitSet(.count = 10, .allocator = allocator)!
    set(.self = $&a, .index = 0)!
    set(.self = $&a, .index = 9)!
    set(.self = $&b, .index = 5)!
    set(.self = $&b, .index = 9)!
    union_with(.self = $&a, .other = &b)!
    if count_set(.self = &a).count != 3 { abort }
    intersect_with(.self = $&a, .other = &b)!
    if count_set(.self = &a).count != 2 { abort }
    if contains(.self = &a, .index = 0)! { abort }
    difference_with(.self = $&a, .other = &b)!
    if count_set(.self = &a).count != 0 { abort }
    mismatched ::= BitSet(.count = 9, .allocator = allocator)!
    match union_with(.self = $&b, .other = &mismatched) { ..ok _ { abort } ..error _ {} }
    if count_set(.self = &b).count != 2 { abort }
    union_with(.self = $&b, .other = &b)!
    if count_set(.self = &b).count != 2 { abort }
    difference_with(.self = $&b, .other = &b)!
    if count_set(.self = &b).count != 0 { abort }
    index :: UIntNative = 0
    while index < 10 {
        set(.self = $&b, .index = index)!
        index = index + 1
    }
    union_with(.self = $&b, .other = &b)!
    intersect_with(.self = $&b, .other = &b)!
    if count_set(.self = &b).count != 10 { abort }
    difference_with(.self = $&b, .other = &b)!
    if count_set(.self = &b).count != 0 { abort }

}

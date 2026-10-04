main() -> (.status_code: Int32 = 0) := {
    bytes :: [3]UInt8 = (255, 255, 99)
    storage ::= view(.array = $&bytes)
    bits ::= unwrap_or_abort(.value = BitSetView(.bytes = storage, .count = 10))
    if count_set(.self = &bits).count != 0 { abort }
    unwrap_or_abort(.value = set(.self = $&bits, .index = 0))
    unwrap_or_abort(.value = set(.self = $&bits, .index = 7))
    unwrap_or_abort(.value = set(.self = $&bits, .index = 9))
    unwrap_or_abort(.value = set(.self = $&bits, .index = 9))
    if count_set(.self = &bits).count != 3 { abort }
    unwrap_or_abort(.value = set(.self = $&bits, .index = 7, .value = false))
    if count_set(.self = &bits).count != 2 { abort }
    match set(.self = $&bits, .index = 10) { ..ok _ { abort } ..error _ {} }
    if count_set(.self = &bits).count != 2 { abort }
    if length(.self = &bits).count != 10 { abort }
    other :: [1]UInt8 = (77)
    narrow ::= view(.array = $&other)
    match BitSetView(.bytes = narrow, .count = 9) { ..ok _ { abort } ..error _ {} }
    if other[0] != 77 { abort }
    native :: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    match BitSetView(.bytes = narrow, .count = maximum) { ..ok _ { abort } ..error _ {} }
    if other[0] != 77 { abort }
    empty ::= unwrap_or_abort(.value = BitSetView(.bytes = narrow, .count = 0))
    if count_set(.self = &empty).count != 0 { abort }
}

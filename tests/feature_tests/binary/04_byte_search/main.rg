main() -> (.status_code: Int32 = 0) := {
    bytes :: [6]UInt8 = (0, 255, 1, 0, 255, 1)
    pattern :: [3]UInt8 = (0, 255, 1)
    a ::= view(.array = &bytes)
    b ::= view(.array = &pattern)
    empty ::= array_view_ro#(.t: UInt8)()
    if compare(.left = a, .right = b).order != 1 { abort }
    if compare(.left = b, .right = a).order != -1 { abort }
    if equals(.left = a, .right = a).ok == false { abort }
    if starts_with(.self = a, .pattern = b).ok == false { abort }
    if ends_with(.self = a, .pattern = b).ok == false { abort }
    if contains(.self = a, .pattern = b).ok == false { abort }
    match find(.self = a, .pattern = b).index {
        ..none { abort }
        ..some hit { if hit.value != 0 { abort } }
    }
    match find_last(.self = a, .pattern = b).index {
        ..none { abort }
        ..some hit { if hit.value != 3 { abort } }
    }
    match find(.self = a, .byte = 255).index {
        ..none { abort }
        ..some hit { if hit.value != 1 { abort } }
    }
    match find(.self = a, .byte = 2).index { ..none {} ..some _ { abort } }
    match find(.self = a, .pattern = empty).index {
        ..none { abort }
        ..some hit { if hit.value != 0 { abort } }
    }
    match find_last(.self = a, .pattern = empty).index {
        ..none { abort }
        ..some hit { if hit.value != 6 { abort } }
    }
    if starts_with(.self = empty, .pattern = empty).ok == false { abort }
    if ends_with(.self = empty, .pattern = empty).ok == false { abort }
    if contains(.self = empty, .pattern = b).ok { abort }
    tail ::= unwrap_or_abort(.value = slice(.self = &a, .start = 3, .count = 3))
    if equals(.left = tail, .right = b).ok == false { abort }
    high :: [1]UInt8 = (255)
    low :: [1]UInt8 = (127)
    if compare(.left = view(.array = &high), .right = view(.array = &low)).order != 1 { abort }
    match find(.self = b, .pattern = a).index { ..none {} ..some _ { abort } }
    match find_last(.self = b, .pattern = a).index { ..none {} ..some _ { abort } }
    missing :: [2]UInt8 = (255, 255)
    match find_last(.self = a, .pattern = view(.array = &missing)).index {
        ..none {} ..some _ { abort }
    }
    overlap :: [3]UInt8 = (7, 7, 7)
    pair :: [2]UInt8 = (7, 7)
    match find_last(.self = view(.array = &overlap), .pattern = view(.array = &pair)).index {
        ..none { abort }
        ..some hit { if hit.value != 1 { abort } }
    }
    boundary ::= unwrap_or_abort(.value = slice(.self = &a, .start = 6, .count = 0))
    if equals(.left = boundary, .right = empty).ok == false { abort }
    match slice(.self = &a, .start = 7, .count = 0) { ..ok _ { abort } ..error _ {} }
    match slice(.self = &a, .start = 5, .count = 2) { ..ok _ { abort } ..error _ {} }

}

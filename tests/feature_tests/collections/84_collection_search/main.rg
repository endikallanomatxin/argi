main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 3))
    if contains(.self = &array, .value = 7).ok { abort }
    push_assume_capacity(.self = $&array, .value = 4)
    push_assume_capacity(.self = $&array, .value = 7)
    push_assume_capacity(.self = $&array, .value = 7)
    index ::= find(.self = &array, .value = 7).index
    match index {
        ..none { abort }
        ..some payload { if payload.value != 1 { abort } }
    }
    view ::= array_view_ro(.array = &array).view
    if contains(.self = &view, .value = 4).ok == false { abort }
    if contains(.self = &view, .value = 9).ok { abort }
    mutable ::= array_view(.array = $&array).view
    if contains(.self = &mutable, .value = 7).ok == false { abort }
    deinit(.self = $&array)
    -- Search returns an independent index, not a reference to destroyed data.
    match index { ..none { abort } ..some payload { if payload.value != 1 { abort } } }
    text : [3]StringView = ("one", "two", "two")
    words ::= array_view_ro(.array = &text).view
    bytes : [3]UInt8 = (116, 119, 111)
    needle :: StringView = (.data = &bytes[0], .length = 3)
    match find(.self = &words, .value = needle).index {
        ..none { abort }
        ..some payload { if payload.value != 1 { abort } }
    }
    if contains(.self = &words, .value = "missing").ok { abort }
}

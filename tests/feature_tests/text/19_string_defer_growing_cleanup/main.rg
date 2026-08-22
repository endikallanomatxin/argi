helper(.allocator: $&Allocator) -> (.ok: Bool) := {
    text ::= String(.allocator = allocator, .capacity = 1)
    #defer deinit(.self = $$&text, .allocator = allocator)

    match push_byte(.self = $$&text, .byte = 65, .allocator = allocator) {
        ..ok _ {
        }
        ..error _ {
            ok = false
            return
        }
    }

    if text.length != 1 {
        ok = false
        return
    }

    ok = true
}

main(.system: System = System()) -> (.status_code: Int32) := {
    if helper(.allocator = system.allocator).ok {
        status_code = 0
    } else {
        status_code = 1
    }
}

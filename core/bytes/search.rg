-- Byte ordering is unsigned and lexicographic. Equal prefixes compare by length.
compare(.left: ArrayViewRO#(.t: UInt8), .right: ArrayViewRO#(.t: UInt8)) -> (.order: Int32 = 0) := {
    count ::= length(&left).count
    other ::= length(&right).count

    if other < count { count = other }
    index :: UIntNative = 0

    while index < count {
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &left, .index = index))
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &right, .index = index))
        if a&< b&{
            order = -1
            return
        }
        if a&> b&{
            order = 1
            return
        }
        index = index + 1
    }

    if length(&left).count < other { order = -1 }
    if length(&left).count > other { order = 1 }
}

equals(.left: ArrayViewRO#(.t: UInt8), .right: ArrayViewRO#(.t: UInt8)) -> (.ok: Bool) := {
    ok = compare(.left = left, .right = right).order == 0
}

_bytes_match_at(
        .self    : ArrayViewRO#(.t: UInt8),
        .pattern : ArrayViewRO#(.t: UInt8),
        .start   : UIntNative
    ) -> (
        .ok : Bool = false
    ) := {
    size ::= length(&self).count
    count ::= length(&pattern).count

    if start > size { return }
    if count > size - start { return }
    offset :: UIntNative = 0

    while offset < count {
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &self, .index = start + offset))
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &pattern, .index = offset))
        if a&!= b&{ return }
        offset = offset + 1
    }

    ok = true
}

-- Empty patterns match at zero forward and at the extent in reverse searches.
find(
        .self    : ArrayViewRO#(.t: UInt8),
        .pattern : ArrayViewRO#(.t: UInt8)
    ) -> (
        .index : ?UIntNative = ..none
    ) := {
    size ::= length(&self).count
    count ::= length(&pattern).count

    if count > size { return }
    last ::= size - count
    start :: UIntNative = 0

    while true {
        if _bytes_match_at(.self = self, .pattern = pattern, .start = start).ok {
            index = ..some(.value = start)
            return
        }
        if start == last { return }
        start = start + 1
    }
}

find_last(
        .self    : ArrayViewRO#(.t: UInt8),
        .pattern : ArrayViewRO#(.t: UInt8)
    ) -> (
        .index : ?UIntNative = ..none
    ) := {
    size ::= length(&self).count
    count ::= length(&pattern).count

    if count > size { return }
    start ::= size - count

    while true {
        if _bytes_match_at(.self = self, .pattern = pattern, .start = start).ok {
            index = ..some(.value = start)
            return
        }
        if start == 0 { return }
        start = start - 1
    }
}

find(.self: ArrayViewRO#(.t: UInt8), .byte: UInt8) -> (.index: ?UIntNative = ..none) := {
    offset :: UIntNative = 0

    while offset < length(&self).count {
        current ::= unwrap_or_abort(.value = get_ro_ref(.self = &self, .index = offset))
        if current&== byte {
            index = ..some(.value = offset)
            return
        }
        offset = offset + 1
    }
}

starts_with(.self: ArrayViewRO#(.t: UInt8), .pattern: ArrayViewRO#(.t: UInt8)) -> (.ok: Bool) := {
    ok = _bytes_match_at(.self = self, .pattern = pattern, .start = 0).ok
}

ends_with(.self: ArrayViewRO#(.t: UInt8), .pattern: ArrayViewRO#(.t: UInt8)) -> (.ok: Bool = false) := {
    size ::= length(&self).count
    count ::= length(&pattern).count

    if count > size { return }
    ok = _bytes_match_at(.self = self, .pattern = pattern, .start = size - count).ok
}

contains(.self: ArrayViewRO#(.t: UInt8), .pattern: ArrayViewRO#(.t: UInt8)) -> (.ok: Bool) := {
    ok = find(.self = self, .pattern = pattern).index ?
}

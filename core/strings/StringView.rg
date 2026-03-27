StringView : Type = (
    .data   : UIntNative
    .length : UIntNative
)

string_view_byte_address(
    .self: &StringView,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = self&.data
    address = base + index
}

bytes_get(
    .view: &StringView,
    .index: UIntNative,
) -> (.byte: UInt8) := {
    addr :: UIntNative = string_view_byte_address(.self = view, .index = index).address
    ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
    byte = ptr&
}

equals(
    .left: &StringView,
    .right: &StringView,
) -> (.ok: Bool) := {
    if left&.length != right&.length {
        ok = false
        return
    }

    i :: UIntNative = 0
    while i < left&.length {
        if bytes_get(.view = left, .index = i).byte != bytes_get(.view = right, .index = i).byte {
            ok = false
            return
        }
        i = i + 1
    }

    ok = true
}

equals(
    .left: &StringView,
    .right: &Char,
) -> (.ok: Bool) := {
    i :: UIntNative = 0
    while i < left&.length {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = right) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            ok = false
            return
        }

        if bytes_get(.view = left, .index = i).byte != ptr& {
            ok = false
            return
        }

        i = i + 1
    }

    terminator_addr :: UIntNative = cast#(.to: UIntNative)(.value = right) + left&.length
    terminator_ptr : &UInt8 = cast#(.to: &UInt8)(.value = terminator_addr)
    ok = terminator_ptr& == 0
}

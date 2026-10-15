StringView: Type = (
    ._data   : &UInt8
    ._length : UIntNative
)

implement ImplicitlyCopyable#(StringView) ()

string_view_byte_address(.self: &StringView, .index: UIntNative) -> (.reference: &UInt8) := {
    if index >= self&._length { abort }
    reference = trusted_reference_offset#(.t: UInt8)(.base = self&._data, .elements = index)
}

_view_get_byte(.view: &StringView, .index: UIntNative) -> (.byte: UInt8) := {
    byte = string_view_byte_address(view, .index = index).reference&
}

equals(.left: StringView, .right: StringView) -> (.ok: Bool) := {
    if left._length != right._length {
        ok = false
        return
    }

    i :: UIntNative = 0

    while i < left._length {
        if [
            bytes_get(.view = &left, .index = i).byte
            != bytes_get(.view = &right, .index = i).byte
        ] {
            ok = false
            return
        }
        i = i + 1
    }

    ok = true
}

implement Equal#(StringView, StringView, (.left: StringView, .right: StringView)) (
    .equal = (.args: (.left: StringView, .right: StringView)) -> (.ok: Bool) {
        ok = equals(.left = args.left, .right = args.right).ok
    }
)

-- Byte views do not promise UTF-8 and never grant writable access to text.
string_bytes(.text: StringView) -> (.bytes: ArrayView#(UInt8)) := {
    if text._length == 0 {
        bytes = empty_array_view#(UInt8)().array
        return
    }
    bytes = _trusted_array_view#(UInt8)(.data = text._data, .length = text._length).array
}

byte_data(.text: StringView) -> (.reference: &UInt8) := {
    reference = text._data
}

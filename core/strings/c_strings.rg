--
-- v1 keeps C-string interop as raw `&Char` plus explicit helpers.
-- There is intentionally no separate nominal `CString` type in core.
--
from_literal(
    .data: &Char,
) -> (.text: &Char) := {
    text = data
}

as_c_string(
    .self: &String,
) -> (.text: &Char) := {
    text = reinterpret_reference#(.from: UInt8, .to: Char)(
        .base = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference,
    ).reference
}

string_view_has_c_string_layout(
    .self: &StringView,
) -> (.ok: Bool) := {
    i :: UIntNative = 0
    while i < self&.length {
        if bytes_get(.view = self, .index = i).byte == 0 {
            ok = false
            return
        }
        i = i + 1
    }

    terminator_ptr ::= reference_offset#(.t: UInt8)(.base = self&.data, .elements = self&.length)
    ok = terminator_ptr& == 0
}

as_c_string(
    .self: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (
    .text: &Char,
    .storage: Allocation,
) := {
    if string_view_has_c_string_layout(.self = &self).ok {
        text = reinterpret_reference#(.from: UInt8, .to: Char)(.base = self.data).reference
        storage = (
            .data = null_reference#(.t: UInt8)().reference,
            .size = 0,
        )
        return
    }

    size :: UIntNative = self.length + 1
    data ::= allocate(.self = allocator, .size = size)

    i :: UIntNative = 0
    while i < self.length {
        ptr ::= mutable_reference_offset#(.t: UInt8)(.base = data, .elements = i).reference
        ptr& = bytes_get(.view = &self, .index = i).byte
        i = i + 1
    }

    nul_ptr ::= mutable_reference_offset#(.t: UInt8)(.base = data, .elements = self.length).reference
    nul_ptr& = 0

    text = reinterpret_reference#(.from: UInt8, .to: Char)(.base = read_reference#(.t: UInt8)(.base = data).reference).reference
    storage = (
        .data = data,
        .size = size,
    )
}

as_view(
    .self: &Char,
) -> (.view: StringView) := {
    view = (
        .data = reinterpret_reference#(.from: Char, .to: UInt8)(.base = self).reference,
        .length = strlen(.string = self).length,
    )
}

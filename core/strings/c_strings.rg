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
) -> (.text: &Char) #returns_dependency(text, self, allocation.data) #trusted_temporal := {
    text = cast#(.to: &Char)(.value = cast#(.to: UIntNative)(.value = self&.allocation.data))
}

string_view_has_c_string_layout(
    .self: &StringView,
) -> (.ok: Bool) #trusted_temporal := {
    i :: UIntNative = 0
    while i < self&.length {
        if bytes_get(.view = self, .index = i).byte == 0 {
            ok = false
            return
        }
        i = i + 1
    }

    terminator_address :: UIntNative = self&.data + self&.length
    terminator_ptr : &UInt8 = cast#(.to: &UInt8)(.value = terminator_address)
    ok = terminator_ptr& == 0
}

as_c_string(
    .self: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (
    .text: &Char,
    .storage: Allocation,
) #trusted_temporal := {
    if string_view_has_c_string_layout(.self = &self).ok {
        zero :: UIntNative = 0
        text = cast#(.to: &Char)(.value = self.data)
        storage = (
            .data = cast#(.to: $&UInt8)(.value = zero),
            .size = 0,
        )
        return
    }

    size :: UIntNative = self.length + 1
    data ::= allocate(.self = allocator, .size = size)

    i :: UIntNative = 0
    while i < self.length {
        ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = data) + i)
        ptr& = bytes_get(.view = &self, .index = i).byte
        i = i + 1
    }

    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = data) + self.length)
    nul_ptr& = 0

    text = cast#(.to: &Char)(.value = cast#(.to: UIntNative)(.value = data))
    storage = (
        .data = data,
        .size = size,
    )
}

as_view(
    .self: &Char,
) -> (.view: StringView) #returns_dependency(view.data, self) #raw_boundary := {
    view = (
        .data = cast#(.to: UIntNative)(.value = self),
        .length = strlen(.string = self).length,
    )
}

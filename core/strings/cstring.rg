CString : Type = (
    .data : UIntNative
)

init(
    .p: $&CString,
    .data: &Char,
) -> () := {
    p& = (
        .data = cast#(.to: UIntNative)(.value = data)
    )
}

from_literal(
    .data: &Char,
) -> (.text: CString) := {
    text = (
        .data = cast#(.to: UIntNative)(.value = data)
    )
}

as_c_string(
    .self: &String,
) -> (.text: CString) := {
    text = (
        .data = cast#(.to: UIntNative)(.value = self&.allocation.data)
    )
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

    terminator_address :: UIntNative = self&.data + self&.length
    terminator_ptr : &UInt8 = cast#(.to: &UInt8)(.value = terminator_address)
    ok = terminator_ptr& == 0
}

as_c_string(
    .self: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (
    .text: CString,
    .storage: Allocation,
) := {
    if string_view_has_c_string_layout(.self = &self).ok {
        zero :: UIntNative = 0
        text = (
            .data = self.data
        )
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

    text = (
        .data = cast#(.to: UIntNative)(.value = data)
    )
    storage = (
        .data = data,
        .size = size,
    )
}

pointer(
    .self: &CString,
) -> (.out: &Char) := {
    out = cast#(.to: &Char)(.value = self&.data)
}

as_view(
    .self: &CString,
) -> (.view: StringView) := {
    ptr ::= pointer(.self = self)
    view = (
        .data = self&.data,
        .length = strlen(.string = ptr).length,
    )
}

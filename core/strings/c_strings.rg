--
-- v1 keeps C-string interop as raw `&Char` plus explicit helpers.
-- There is intentionally no separate nominal `CString` type in core.
--
OwnedCString : Type = (
    .text: &Char
    .storage: Allocation
)

from_literal(
    .data: &Char,
) -> (.text: &Char) := {
    text = data
}

as_c_string(
    .self: &String,
) -> (.text: &Char) := {
    text = reinterpret_reference#(.from: UInt8, .to: Char)(.base = self&.allocation.data).reference
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
) -> (.result: Errable#(.t: OwnedCString, .reasons: (..out_of_memory))) := {
    size :: UIntNative = self.length + 1
    allocated ::= allocate(.self = allocator, .size = size)
    match allocated {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            allocation ::= ~payload
            data ::= allocation.data

            i :: UIntNative = 0
            while i < self.length {
                ptr ::= mutable_reference_offset#(.t: UInt8)(.base = data, .elements = i).reference
                ptr& = bytes_get(.view = &self, .index = i).byte
                i = i + 1
            }

            nul_ptr ::= mutable_reference_offset#(.t: UInt8)(.base = data, .elements = self.length).reference
            nul_ptr& = 0

            text ::= reinterpret_reference#(.from: UInt8, .to: Char)(.base = read_reference#(.t: UInt8)(.base = data).reference).reference
            result = ..ok (.text = text, .storage = ~allocation)
        }
    }
}

as_view(
    .self: &Char,
) -> (.view: StringView) := {
    view = (
        .data = reinterpret_reference#(.from: Char, .to: UInt8)(.base = self).reference,
        .length = strlen(.string = self).length,
    )
}

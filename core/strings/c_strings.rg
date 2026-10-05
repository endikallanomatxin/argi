--
-- v1 keeps C-string interop as raw `&Char` plus explicit helpers.
-- There is intentionally no separate nominal `CString` type in core.
--
OwnedCString: Type = (
    .text    : &Char
    .storage : Allocation
)

from_literal(
        .data : &Char,
    ) -> (
        .text : &Char
    ) := {
    text = data
}

as_c_string(
        .self : &String,
    ) -> (
        .text : &Char
    ) := {
    text = trusted_reinterpret_reference#(.from: UInt8, .to: Char)(
        .base = _trusted_allocation_byte_ro(.allocation = &self&.allocation, .offset = 0).reference
    ).reference
}

string_view_has_c_string_layout(
        .self : &StringView,
    ) -> (
        .ok : Bool
    ) := {
    i :: UIntNative = 0

    while i < self&.length {
        if bytes_get(.view = self, .index = i).byte == 0 {
            ok = false
            return
        }
        i = i + 1
    }

    terminator_ptr ::= trusted_reference_offset#(.t: UInt8)(
        .base     = self&.data
        .elements = self&.length
    )
    ok = terminator_ptr&== 0
}

as_c_string(
        .self      : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(OwnedCString, (..out_of_memory))
    ) := {
    assume allocator

    size :: UIntNative = self.length + 1
    allocated ::= allocate(allocator, .size = size)

    match allocated {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~payload {
            allocation ::= ~payload
            data ::= _trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference

            i :: UIntNative = 0
            while i < self.length {
                ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(.base = data, .elements = i).reference
                ptr&= bytes_get(.view = &self, .index = i).byte
                i = i + 1
            }

            nul_ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                .base     = data
                .elements = self.length
            ).reference
            nul_ptr&= 0

            text ::= trusted_reinterpret_reference#(.from: UInt8, .to: Char)(
                .base = read_reference#(.t: UInt8)(.base = data).reference
            ).reference
            result = ..ok(.text = text, .storage = ~allocation)
        }
    }
}

as_view(
        .self : &Char,
    ) -> (
        .view : StringView
    ) := {
    view = (
        .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = self).reference
        .length = strlen(.string = self).length
    )
}

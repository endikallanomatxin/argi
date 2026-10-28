--
-- v1 keeps C-string interop as raw `&CChar` plus explicit helpers.
-- There is intentionally no separate nominal `CString` type in core.
--
OwnedCString := (
    .text    : &CChar
    .storage : Allocation
)

from_literal := (.data: &CChar) -> (.text: &CChar) {
    text = data
}

as_c_string := (.self: &String) -> (.text: &CChar) {
    text = trusted_reinterpret_reference#(.from: UInt8, .to: CChar)(
        .base = _trusted_allocation_byte_ro(
            .allocation = &self&._allocation, .offset = 0
        ).reference
    ).reference
}

copy_c_string := #(.Provider: Type: Allocator#(Provider)) (
    .self: StringView, .allocator: $&Provider
) -> (.result: Errable#(OwnedCString, (..out_of_memory))) {
    assume allocator

    if self._length == integer_limits(.value = self._length).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    size :: UIntNative = self._length + 1
    allocated ::= Allocator#(Provider).allocate(.self = allocator, .size = size, .alignment = 1)

    match allocated {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~payload {
            allocation ::= ~payload
            data ::= _trusted_allocation_byte_rw(
                .allocation = $&allocation, .offset = 0
            ).reference

            i :: UIntNative = 0
            while i < self._length {
                ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                    .base = data, .elements = i
                ).reference
                ptr&= unwrap_or_abort(.value = bytes_get(.view = &self, .index = i))
                i = i + 1
            }

            nul_ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                .base = data, .elements = self._length
            ).reference
            nul_ptr&= 0

            text ::= trusted_reinterpret_reference#(.from: UInt8, .to: CChar)(
                .base = read_reference#(.t: UInt8)(.base = data).reference
            ).reference
            result = ..ok(.text = text, .storage = ~allocation)
        }
    }
}

_c_string_bytes := (.text: &CChar) -> (.bytes: ArrayView#(UInt8)) {
    size ::= c_string_length(.text = text).length
    if size == 0 {
        bytes = empty_array_view#(UInt8)().array
        return
    }
    bytes = _trusted_array_view#(UInt8)(
        .data = trusted_reinterpret_reference#(.from: CChar, .to: UInt8)(
            .base = text
        ).reference
        .length = size
    ).array
}

string_from_c_string := #(.Provider: Type: Allocator) (.text: &CChar, .allocator: $&Provider) -> (
    .result : Errable#(String, (..invalid_utf8, ..out_of_memory))
) {
    assume allocator
    result = string_from_bytes(.bytes = _c_string_bytes(.text = text), .allocator = allocator)
}

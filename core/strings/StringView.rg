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

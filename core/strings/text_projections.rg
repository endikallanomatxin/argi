TextViewOf#(.Source: Type): Contract = (
    .text_view: (.self: Source) -> (.view: StringView)
)
as_view#(.Source: Type: TextViewOf#(Source)) := (.self: Source) -> (.view: StringView) {
    view = TextViewOf#(Source).text_view(.self = self)
}
implement TextViewOf#(&String) (.text_view = _string_text_view)
implement TextViewOf#(&Char) (.text_view = _c_text_view)

TextBytes#(.Text: Type): Contract = (
    .byte_at: (.view: &Text, .index: UIntNative) -> (.byte: UInt8)
)
bytes_get#(.Text: Type: TextBytes#(Text)) := (.view: &Text, .index: UIntNative) -> (.byte: UInt8) {
    byte = TextBytes#(Text).byte_at(.view = view, .index = index)
}
implement TextBytes#(String) (.byte_at = _string_get_byte)
implement TextBytes#(StringView) (.byte_at = _view_get_byte)

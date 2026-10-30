implement Viewable#(&String) (
    .Result    : Type = StringView
    .make_view = _string_text_view
)

TextBytes#(.Text: Type): Contract = (
    .measure_bytes : (.self: &Text) -> (.count: UIntNative)
    .byte_at       : (.view: &Text, .index: UIntNative) -> (
        .result : Errable#(UInt8, (..out_of_bounds))
    )
)

bytes_get := #(.Text: Type: TextBytes#(Text)) (.view: &Text, .index: UIntNative) -> (
    .result : Errable#(UInt8, (..out_of_bounds))
) {

    result = TextBytes#(Text).byte_at(.view = view, .index = index)
}

implement TextBytes#(String) (
    .byte_at       = _string_get_byte,
    .measure_bytes = _string_byte_length
)

implement TextBytes#(StringView) (
    .byte_at       = _view_get_byte,
    .measure_bytes = _view_byte_length
)

_string_byte_length := (.self: &String) -> (.count: UIntNative) { count = self&._length }

_view_byte_length := (.self: &StringView) -> (.count: UIntNative) { count = self&._length }

byte_length := #(.Text: Type: TextBytes#(Text)) (.self: &Text) -> (.count: UIntNative) {
    count = TextBytes#(Text).measure_bytes(.self = self)
}

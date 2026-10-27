ByteCursor#(.Cursor: Type): Contract = (
    .cursor_position  : (.self: &Cursor) -> (.count: UIntNative)
    .cursor_remaining : (.self: &Cursor) -> (.count: UIntNative)
    .cursor_skip      : (.self: $&Cursor, .count: UIntNative) -> (
        .result : Errable#(Void, (..out_of_bounds))
    )
)

position := #(.Cursor: Type: ByteCursor#(Cursor)) (.self: &Cursor) -> (.count: UIntNative) {
    count = ByteCursor#(Cursor).cursor_position(.self = self)
}

remaining := #(.Cursor: Type: ByteCursor#(Cursor)) (.self: &Cursor) -> (.count: UIntNative) {
    count = ByteCursor#(Cursor).cursor_remaining(.self = self)
}

skip := #(.Cursor: Type: ByteCursor#(Cursor)) (.self: $&Cursor, .count: UIntNative) -> (
    .result : Errable#(Void, (..out_of_bounds))
) {
    result = ByteCursor#(Cursor).cursor_skip(.self = self, .count = count)
}

implement ByteCursor#(ByteReader) (
    .cursor_position  = _byte_reader_position
    .cursor_remaining = _byte_reader_remaining
    .cursor_skip      = _byte_reader_skip
)

implement ByteCursor#(ByteWriter) (
    .cursor_position  = _byte_writer_position
    .cursor_remaining = _byte_writer_remaining
    .cursor_skip      = _byte_writer_skip
)

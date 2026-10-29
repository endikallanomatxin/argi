ByteSource#(.Stream: Type): Contract = (
    .read_byte : (.self: $&Stream) -> (.result: Int32) where {}
)

Cursor := (.next: Int32 = 1)

Buffered := #(.Base: Type) (.base: Base)

implement ByteSource#(Cursor) (
    .read_byte = (
        .self         : $&Cursor,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Int32) {
        assume error_tracer

        result = self&.next
        self&.next = self&.next + 1
    }
)

implement#(.T: Type: ByteSource#(T)) ByteSource#(Buffered#(.Base: T)) (
    .read_byte = (
        .self         : $&Buffered#(T),
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Int32) {
        assume error_tracer

        result = ByteSource#(T).read_byte($&self&.base).result
    }
)

main := () -> (.status_code: Int32 = 0) {
    stream ::= Buffered#(Buffered#(Cursor))(.base = Buffered#(Cursor)(.base = Cursor()))
    if ByteSource#(Buffered#(Buffered#(Cursor))).read_byte($&stream).result != 1 { abort }
    if ByteSource#(Buffered#(Buffered#(Cursor))).read_byte($&stream).result != 2 { abort }
    erased ::= to_virtual#(.contract: ByteSource)(.value = $&stream)
    if ByteSource#().read_byte($&erased) != 3 { abort }
    if ByteSource#().read_byte($&erased) != 4 { abort }
}

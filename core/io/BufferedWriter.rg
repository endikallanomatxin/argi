-- Borrows both the writer and an initialized byte buffer. Construction does
-- not allocate. Explicit flush reports errors; cleanup flushes best-effort.
-- Failed writes discard pending bytes because partial progress is unknown.
BufferedWriter := #(.base_type: Type: Writer#(base_type)) (
    .base   : $&base_type
    .buffer : MutableArrayView#(.t: UInt8)
    .length : UIntNative
)

implement#(.base_type: Type: Writer#(base_type)) Init#(
    BufferedWriter#(.base_type: base_type),
    (
        .base   : $&base_type,
        .buffer : MutableArrayView#(.t: UInt8) = view($&zeroed#(.t: [4096]UInt8)())
    )
) (
    .Result : Type = BufferedWriter#(.base_type: base_type)
    .init   = (
        .args : (
            .base   : $&base_type,
            .buffer : MutableArrayView#(.t: UInt8) = view($&zeroed#(.t: [4096]UInt8)())
        )
    ) -> (.result: Result) {
        base ::= args.base
        buffer ::= args.buffer

        result = (.base = base, .buffer = buffer, .length = 0)
    }
)

implement#(.base_type: Type: Writer#(base_type)) Deinit#(BufferedWriter#(.base_type: base_type)) (
    .deinit = (.self: $&BufferedWriter#(.base_type: base_type)) -> () {
        buffered_writer_flush(self)
    }
)

buffered_writer_flush := #(.base_type: Type: Writer#(base_type)) (
    .self : $&BufferedWriter#(.base_type: base_type)
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {
    i :: UIntNative = 0

    while i < self&.length {
        remaining ::= self&.length - i
        view ::= unwrap_or_abort(.value = slice(&self&.buffer, .start = i, .count = remaining))
        wrote ::= write(self&.base, .value = view)
        if is(.value = wrote, .variant = ..error) {
            self&.length = 0
            result = ..error(.reason = wrote ..error.reason)
            return
        }
        count ::= wrote ..ok
        if count == 0 or count > remaining {
            self&.length = 0
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        i = i + count
    }

    flushed ::= Writer#().flush(.self = self&.base)

    if is(.value = flushed, .variant = ..error) {
        self&.length = 0
        result = ..error(.reason = flushed ..error.reason)
        return
    }

    self&.length = 0

    result = ..ok Void()
}

implement#(.base_type: Type: Writer#(base_type)) Writer#(BufferedWriter#(.base_type: base_type)) (
    .write_byte = (.self: $&BufferedWriter#(.base_type: base_type), .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        if length(&self&.buffer) == 0 {
            result = Writer#().write_byte(self&.base, .byte = byte)
            return
        }

        ptr ::= unwrap_or_abort(
            .value = get_mutable_reference($&self&.buffer, .index = self&.length)
        )
        ptr&= byte
        next_length ::= self&.length + 1
        self&.length = next_length

        if next_length == length(&self&.buffer) {
            result = buffered_writer_flush(self)
            return
        }

        result = ..ok Void()
    }

    .flush = (.self: $&BufferedWriter#(.base_type: base_type)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = buffered_writer_flush(self)
    }
)

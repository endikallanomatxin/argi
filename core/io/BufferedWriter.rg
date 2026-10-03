-- Borrows both the writer and an initialized byte buffer. Construction does
-- not allocate. Explicit flush reports errors; cleanup flushes best-effort.
-- Failed writes discard pending bytes because partial progress is unknown.
BufferedWriter#(.base_type: Type: Writer) : Type = (
    .base: $&base_type
    .buffer: ArrayView#(.t: UInt8)
    .length: UIntNative
)

BufferedWriter init#(.base_type: Type: Writer)(.base: $&base_type,
    .buffer: ArrayView#(.t: UInt8),
) -> (.result: BufferedWriter#(.base_type: base_type)) := {
    result = (.base = base, .buffer = buffer, .length = 0)
}

deinit#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> () := {
    buffered_writer_flush(.self = self)
}

buffered_writer_flush#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < self&.length {
        remaining ::= self&.length - i
        view ::= unwrap_or_abort(.value = slice(.self = &self&.buffer, .start = i, .count = remaining))
        wrote ::= write(.self = self&.base, .buffer = view)
        if is(.value = wrote, .variant = ..error) {
            self&.length = 0
            result = ..error(.reason = wrote..error.reason)
            return
        }
        count ::= wrote..ok
        if count == 0 or count > remaining {
            self&.length = 0
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        i = i + count
    }

    flushed ::= flush(.self = self&.base)
    if is(.value = flushed, .variant = ..error) {
        self&.length = 0
        result = ..error(.reason = flushed..error.reason)
        return
    }

    self&.length = 0
    result = ..ok Void()
}

write_byte#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type), .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if length(.self = &self&.buffer) == 0 {
        result = write_byte(.self = self&.base, .byte = byte)
        return
    }
    ptr ::= unwrap_or_abort(.value = get_rw_ref(.self = $&self&.buffer, .index = self&.length))
    ptr& = byte
    next_length ::= self&.length + 1
    self&.length = next_length

    if next_length == length(.self = &self&.buffer) {
        result = buffered_writer_flush(.self = self)
        return
    }

    result = ..ok Void()
}

flush#(.base_type: Type: Writer)(.self: $&BufferedWriter#(.base_type: base_type)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = buffered_writer_flush(.self = self)
}

BufferedWriter#(.base_type: Type: Writer) implements Writer

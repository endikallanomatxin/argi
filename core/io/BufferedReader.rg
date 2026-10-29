-- Borrows both the reader and an initialized byte buffer. Construction does
-- not allocate. Returned bytes are copied values independent of the buffer.
BufferedReader := #(.base_type: Type: Reader#(base_type)) (
    .base   : $&base_type
    .buffer : MutableArrayView#(.t: UInt8)
    .start  : UIntNative
    .end    : UIntNative
)

BufferedReaderInitArgs: Type = #(.base_type: Type: Reader#(base_type)) (
    .base   : $&base_type,
    .buffer : MutableArrayView#(.t: UInt8) = view($&zeroed#(.t: [4096]UInt8)())
)

implement#(.base_type: Type: Reader#(base_type)) Init#(
    BufferedReader#(.base_type: base_type), BufferedReaderInitArgs#(base_type)
) (
    .Result : Type = BufferedReader#(.base_type: base_type)

    .init = BufferedReaderInitArgs#(base_type) -> (.result: Result) {
        result = (.base = base, .buffer = buffer, .start = 0, .end = 0)
    }
)

implement#(.base_type: Type: Reader#(base_type)) Reader#(BufferedReader#(.base_type: base_type)) (
    .read_byte = (
        .self         : $&BufferedReader#(.base_type: base_type),
        .error_tracer : $&Virtual#(.contract: ErrorTracer)        = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(ReadByte, (..stream_read_failed))) {
        assume error_tracer

        if self&.start < self&.end {
            byte ::= unwrap_or_abort(.value = get(&self&.buffer, .index = self&.start))
            self&.start = self&.start + 1
            result = ..ok ..ok byte
            return
        }

        capacity ::= length(&self&.buffer).count
        if capacity == 0 {
            result = Reader#().read_byte(self&.base)
            return
        }

        match read(self&.base, .buffer = self&.buffer) {
            ..error ~error { result = ..error ~error }
            ..ok count {
                if count > capacity { abort }
                self&.start = 0
                self&.end = count
                if count == 0 {
                    result = ..ok ..end
                    return
                }
                self&.start = 1
                result = ..ok ..ok unwrap_or_abort(.value = get(&self&.buffer, .index = 0))
            }
        }
    }
)

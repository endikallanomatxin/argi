-- Native copies write initialized binary storage; only text results are decoded.
_native_byte_buffer := #(.Provider: Type: Allocator) (
    .count        : UIntNative,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(DynamicArray#(UInt8), (..out_of_memory))) {
    assume error_tracer

    assume allocator
    bytes ::= DynamicArray#(UInt8)(.capacity = count)!
    index :: UIntNative = 0
    while index < count {
        push_assume_capacity($&bytes, .value = 0)
        index = index + 1
    }
    result = ..ok ~bytes
}

_native_buffer_address := (.bytes: MutableArrayView#(UInt8)) -> (.address: RawPointer#(UInt8)) {
    value :: UIntNative = 0
    if length(&bytes).count != 0 {
        value = data(&bytes).pointer | convert#(.to: UIntNative)(_)
    }
    address = raw_pointer#(UInt8)(.address = value)
}

-- The native text-copy protocol promises strict UTF-8; invalid output is a
-- violated native invariant, while allocation failure remains recoverable.
_native_text := #(.Provider: Type: Allocator) (
    .bytes        : ArrayView#(UInt8),
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    assume allocator
    match string_from_bytes(.bytes = bytes) {
        ..ok ~text { result = ..ok ~text }
        ..error failure {
            if failure.reason == ..invalid_utf8 { abort }
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

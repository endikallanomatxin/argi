Limits := (
    .max_head_bytes       : UIntNative = 16384
    .max_headers          : UIntNative = 100
    .max_body_bytes       : UIntNative = 1048576
    .max_chunk_line_bytes : UIntNative = 1024
    .max_trailer_bytes    : UIntNative = 16384
)

implement ImplicitlyCopyable#(Limits) ()

LimitsInitArgs: Type = (
    .max_head_bytes       : UIntNative = 16384
    .max_headers          : UIntNative = 100
    .max_body_bytes       : UIntNative = 1048576
    .max_chunk_line_bytes : UIntNative = 1024
    .max_trailer_bytes    : UIntNative = 16384
)

implement Init#(Limits, LimitsInitArgs) (
    .Result : Type = Limits
    .init   = LimitsInitArgs -> (.result: Result) {
        result = (
            .max_head_bytes       = max_head_bytes
            .max_headers          = max_headers
            .max_body_bytes       = max_body_bytes
            .max_chunk_line_bytes = max_chunk_line_bytes
            .max_trailer_bytes    = max_trailer_bytes
        )
    }
)

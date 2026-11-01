HttpReasons: Type = (
    ..invalid_request,
    ..invalid_header,
    ..invalid_framing,
    ..unsupported_transfer_encoding,
    ..unsupported_expectation,
    ..head_too_large,
    ..too_many_headers,
    ..body_too_large,
    ..unexpected_eof,
    ..invalid_chunk,
    ..invalid_response,
    ..invalid_state,
    ..invalid_stream_buffer,
    ..stream_read_failed,
    ..stream_write_failed,
    ..stream_flush_failed
)

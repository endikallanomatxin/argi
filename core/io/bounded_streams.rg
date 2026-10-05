_bounded_stream_maximum() -> (.value: UIntNative) := {
    maximum :: UIntNative = 0
    byte_index :: UIntNative = 0
    native_bytes ::= size_of(.type = UIntNative)

    while byte_index < native_bytes {
        maximum = maximum * 256 + 255
        byte_index = byte_index + 1
    }

    value = maximum
}

StreamCopyEnd: Type = (..end, ..limit)

StreamCopyEnd implements ImplicitlyCopyable

StreamCopyResult: Type = (.count: UIntNative, .termination: StreamCopyEnd)

StreamCopyResult implements ImplicitlyCopyable
..size_limit_exceeded

-- A limit is a stopping point, not an assertion that the source ended. No
-- lookahead byte is consumed, including when the limit is zero or exactly met.
copy_stream_limited(
        .reader : $&BlockReader,
        .writer : $&BlockWriter,
        .buffer : ArrayView#(.t: UInt8),
        .limit  : UIntNative
    ) -> (
        .result : Errable#(
            StreamCopyResult,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer
            )
        )
    ) := {
    copied :: UIntNative = 0

    if limit == 0 {
        result = ..ok(.count = 0, .termination = ..limit)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    while copied < limit {
        request ::= limit - copied
        if request > size { request = size }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(reader, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok(.count = copied, .termination = ..end)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        write_all(writer, .buffer = as_readonly(&prefix).view)!
        copied = copied + got
    }

    result = ..ok(.count = copied, .termination = ..limit)
}

copy_stream_limited(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&BlockWriter,
        .buffer : ArrayView#(.t: UInt8),
        .limit  : UIntNative
    ) -> (
        .result : Errable#(
            StreamCopyResult,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer
            )
        )
    ) := {
    copied :: UIntNative = 0

    if limit == 0 {
        result = ..ok(.count = 0, .termination = ..limit)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    while copied < limit {
        request ::= limit - copied
        if request > size { request = size }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(reader, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok(.count = copied, .termination = ..end)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        write_all(writer, .buffer = as_readonly(&prefix).view)!
        copied = copied + got
    }

    result = ..ok(.count = copied, .termination = ..limit)
}

copy_stream_limited(
        .reader : $&BlockReader,
        .writer : $&Virtual#(.abstract: BlockWriter),
        .buffer : ArrayView#(.t: UInt8),
        .limit  : UIntNative
    ) -> (
        .result : Errable#(
            StreamCopyResult,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer
            )
        )
    ) := {
    copied :: UIntNative = 0

    if limit == 0 {
        result = ..ok(.count = 0, .termination = ..limit)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    while copied < limit {
        request ::= limit - copied
        if request > size { request = size }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(reader, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok(.count = copied, .termination = ..end)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        write_all(writer, .buffer = as_readonly(&prefix).view)!
        copied = copied + got
    }

    result = ..ok(.count = copied, .termination = ..limit)
}

copy_stream_limited(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&Virtual#(.abstract: BlockWriter),
        .buffer : ArrayView#(.t: UInt8),
        .limit  : UIntNative
    ) -> (
        .result : Errable#(
            StreamCopyResult,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer
            )
        )
    ) := {
    copied :: UIntNative = 0

    if limit == 0 {
        result = ..ok(.count = 0, .termination = ..limit)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    while copied < limit {
        request ::= limit - copied
        if request > size { request = size }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(reader, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok(.count = copied, .termination = ..end)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        write_all(writer, .buffer = as_readonly(&prefix).view)!
        copied = copied + got
    }

    result = ..ok(.count = copied, .termination = ..limit)
}

-- Return complete binary data or release the partial owner on every error.
-- Capacity growth is capped independently of the caller's scratch extent.
read_all_limited(
        .self      : $&BlockReader,
        .buffer    : ArrayView#(.t: UInt8),
        .limit     : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            String,
            (
                ..stream_read_failed,
                ..invalid_stream_buffer,
                ..size_limit_exceeded,
                ..size_overflow,
                ..out_of_memory
            )
        )
    ) := {
    assume allocator
    maximum ::= _bounded_stream_maximum().value

    if limit >= maximum {
        result = ..error(.reason = ..size_overflow)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    initial ::= size

    if initial > limit { initial = limit }
    out ::= string_with_capacity(.allocator = allocator, .capacity = initial)!

    while out.length < limit {
        request ::= limit - out.length
        if request > size { request = size }
        needed ::= out.length + request
        current ::= capacity(&out).value
        -- Reserve before the read so allocation failure consumes no new chunk.
        if needed > current {
            grown ::= current
            while grown < needed {
                if grown > limit / 2 { grown = limit } else { grown = grown * 2 }
                if grown == 0 { grown = 1 }
            }
            fresh ::= string_with_capacity(.allocator = allocator, .capacity = grown)!
            push_view($&fresh, .view = as_view(&out), .allocator = allocator)!
            deinit(.self = $&out, .allocator = allocator)
            out = ~fresh
        }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(self, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok ~out
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        string_append_bytes($&out, .source = as_readonly(&prefix).view)
    }
    -- A single scratch byte distinguishes exact EOF from excess data.
    probe ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = 1))
    got ::= read_block(self, .buffer = probe)!

    if got > 1 { abort }
    if got != 0 {
        result = ..error(.reason = ..size_limit_exceeded)
        return
    }

    result = ..ok ~out
}

read_all_limited(
        .self      : $&Virtual#(.abstract: BlockReader),
        .buffer    : ArrayView#(.t: UInt8),
        .limit     : UIntNative,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            String,
            (
                ..stream_read_failed,
                ..invalid_stream_buffer,
                ..size_limit_exceeded,
                ..size_overflow,
                ..out_of_memory
            )
        )
    ) := {
    assume allocator
    maximum ::= _bounded_stream_maximum().value

    if limit >= maximum {
        result = ..error(.reason = ..size_overflow)
        return
    }

    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    initial ::= size

    if initial > limit { initial = limit }
    out ::= string_with_capacity(.allocator = allocator, .capacity = initial)!

    while out.length < limit {
        request ::= limit - out.length
        if request > size { request = size }
        needed ::= out.length + request
        current ::= capacity(&out).value
        -- Reserve before the read so allocation failure consumes no new chunk.
        if needed > current {
            grown ::= current
            while grown < needed {
                if grown > limit / 2 { grown = limit } else { grown = grown * 2 }
                if grown == 0 { grown = 1 }
            }
            fresh ::= string_with_capacity(.allocator = allocator, .capacity = grown)!
            push_view($&fresh, .view = as_view(&out), .allocator = allocator)!
            deinit(.self = $&out, .allocator = allocator)
            out = ~fresh
        }
        destination ::= unwrap_or_abort(
            .value = slice(&buffer, .start = 0, .count = request)
        )
        got ::= read_block(self, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok ~out
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        string_append_bytes($&out, .source = as_readonly(&prefix).view)
    }
    -- A single scratch byte distinguishes exact EOF from excess data.
    probe ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = 1))
    got ::= read_block(self, .buffer = probe)!

    if got > 1 { abort }
    if got != 0 {
        result = ..error(.reason = ..size_limit_exceeded)
        return
    }

    result = ..ok ~out
}

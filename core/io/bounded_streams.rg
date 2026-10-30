StreamCopyEnd: Type = (..end, ..limit)

implement ImplicitlyCopyable#(StreamCopyEnd) ()

StreamCopyResult := (.count: UIntNative, .termination: StreamCopyEnd)

implement ImplicitlyCopyable#(StreamCopyResult) ()

..size_limit_exceeded

-- A limit is a stopping point, not an assertion that the source ended. No
-- lookahead byte is consumed, including when the limit is zero or exactly met.
copy_stream_limited := #(
    .ReaderType: Type: BlockReader#(ReaderType), .WriterType: Type: BlockWriter#(WriterType)
) (
    .reader : $&ReaderType,
    .writer : $&WriterType,
    .buffer : MutableArrayView#(.t: UInt8),
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
) {

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
        destination ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = request))
        got ::= BlockReader#().read_block(reader, .buffer = destination)!
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
read_all_limited := #(
    .SelfType: Type: BlockReader#(SelfType), .AllocatorType: Type: Allocator#(AllocatorType)
) (
    .self      : $&SelfType,
    .buffer    : MutableArrayView#(.t: UInt8),
    .limit     : UIntNative,
    .allocator : $&AllocatorType
) -> (
    .result : Errable#(
        DynamicArray#(UInt8),
        (
            ..stream_read_failed,
            ..invalid_stream_buffer,
            ..size_limit_exceeded,
            ..out_of_memory
        )
    )
) {

    assume allocator
    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    initial ::= size

    if initial > limit { initial = limit }
    out ::= DynamicArray#(UInt8)(.allocator = allocator, .capacity = initial)!

    while length(&out).count < limit {
        request ::= limit - length(&out).count
        if request > size { request = size }
        needed ::= length(&out).count + request
        current ::= capacity(&out).count
        -- Reserve before the read so allocation failure consumes no new chunk.
        if needed > current {
            grown ::= current
            while grown < needed {
                if grown > limit / 2 { grown = limit } else { grown = grown * 2 }
                if grown == 0 { grown = 1 }
            }
            -- Generic array growth may exceed a requested minimum. Allocate
            -- the exact bounded capacity before consuming another source chunk.
            fresh ::= DynamicArray#(UInt8)(.allocator = allocator, .capacity = grown)!
            for byte in out { push_assume_capacity($&fresh, .value = byte) }
            deinit(.self = $&out)
            out = ~fresh
        }
        destination ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = request))
        got ::= BlockReader#().read_block(self, .buffer = destination)!
        if got > request { abort }
        if got == 0 {
            result = ..ok ~out
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        index :: UIntNative = 0
        while index < got {
            byte ::= unwrap_or_abort(.value = get(&prefix, .index = index))
            push_assume_capacity($&out, .value = byte)
            index = index + 1
        }
    }
    -- A single scratch byte distinguishes exact EOF from excess data.
    probe ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = 1))
    got ::= BlockReader#().read_block(self, .buffer = probe)!

    if got > 1 { abort }
    if got != 0 {
        result = ..error(.reason = ..size_limit_exceeded)
        return
    }

    result = ..ok ~out
}

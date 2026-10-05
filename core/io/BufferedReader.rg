BufferedReader#(.base_type: Type: Reader): Type = (
    --
    -- Owning buffered reader wrapper.
    --
    -- The wrapper owns only its internal byte buffer. The underlying `.base`
    -- stream remains borrowed and is not closed or deinitialized here.
    --
    -- Bytes returned by `read_byte()` are copied out of the buffer, so callers
    -- do not borrow storage tied to this wrapper's lifetime.
    --
    .base     : $&base_type
    .buffer   : Allocation
    .capacity : UIntNative
    .start    : UIntNative
    .end      : UIntNative
)

BufferedReader init#(
        .base_type : Type: Reader
    )(
        .allocator : $&Allocator,
        .base      : $&base_type,
        .capacity  : UIntNative,
    ) -> (
        .result : Errable#(.t: BufferedReader#(.base_type: base_type), .reasons: (..out_of_memory))
    ) := {
    constructed :: BufferedReader#(.base_type: base_type)

    assume allocator

    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    buffer ::= allocate(.self = allocator, .size = actual_capacity)!
    -- The refill view contains initialized bytes before any native read.
    index :: UIntNative = 0

    while index < actual_capacity {
        byte ::= _trusted_allocation_byte_rw(.allocation = $&buffer, .offset = index).reference
        byte&= 0
        index = index + 1
    }

    constructed = (
        .base     = base
        .buffer   = ~buffer
        .capacity = actual_capacity
        .start    = 0
        .end      = 0
    )

    result = ..ok ~constructed
}

BufferedReader deinit#(
        .base_type : Type: Reader
    )(
        .self      : $&BufferedReader#(.base_type: base_type),
        .allocator : $&Allocator,
    ) -> () := {
    assume allocator

    deinit(.self = $&self&.buffer)
}

read_byte#(
        .base_type : Type: Reader
    )(
        .self : $&BufferedReader#(.base_type: base_type)
    ) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) := {
    if self&.start < self&.end {
        ptr ::= _trusted_allocation_byte_ro(.allocation = &self&.buffer, .offset = self&.start).reference
        result = ..ok ..ok ptr&
        self&.start = self&.start + 1
        return
    }

    if self&.capacity == 0 {
        result = read_byte(.self = self&.base)
        return
    }

    storage ::= _trusted_allocation_byte_rw(.allocation = $&self&.buffer, .offset = 0).reference
    buffer_view ::= _trusted_array_view#(.t: UInt8)(.data = storage, .length = self&.capacity).array

    match read(.self = self&.base, .buffer = buffer_view) {
        ..error _ { result = ..error(.reason = ..stream_read_failed) }
        ..ok count {
            if count > self&.capacity { abort }
            self&.start = 0
            self&.end = count
            if count == 0 {
                result = ..ok ..end
                return
            }
            self&.start = 1
            result = ..ok ..ok storage&
        }
    }
}

BufferedReader#(.base_type: Type: Reader) implements Reader

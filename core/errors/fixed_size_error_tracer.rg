ErrorTraceEntry: Type = (.location: SourceLocationId, .context_length: UIntNative)

ErrorTraceEntry satisfies ImplicitlyCopyable

-- Fixed slots bound both context copy work and memory use. The first half
-- retains early frames; the second half replaces recent frames in a ring.
-- All errors referring to this tracer share the same diagnostic log.
FixedSizeErrorTracer: Type = (
    ._buffer   : ArrayView#(.t: UInt8)
    ._capacity : UIntNative
    ._length   : UIntNative
    ._next     : UIntNative
    ._dropped  : Bool
)

_error_trace_stride() -> (.size: UIntNative) := {
    size = size_of(.type = ErrorTraceEntry) + 128
}

-- The buffer is initialized caller-owned storage, not an allocation owned by
-- the tracer. Trailing bytes that do not fit a complete slot are unused.
FixedSizeErrorTracer init(.buffer: ArrayView#(.t: UInt8)) -> (.result: FixedSizeErrorTracer) := {
    capacity ::= length(&buffer).count / _error_trace_stride().size

    result = (
        ._buffer   = buffer
        ._capacity = capacity
        ._length   = 0
        ._next     = capacity / 2
        ._dropped  = false
    )
}

-- Ending the tracer invalidates its handles without releasing caller storage.
FixedSizeErrorTracer deinit(.self: $&FixedSizeErrorTracer) -> () := {}

_error_trace_header(
        .self  : $&FixedSizeErrorTracer,
        .index : UIntNative
    ) -> (
        .header : ArrayView#(.t: UInt8)
    ) := {
    assume error_tracer ::= $&noop_error_tracer

    if index >= self&._capacity { abort }
    header = unwrap_or_abort(
        .value = slice(
            &self&._buffer
            .start = index * _error_trace_stride().size
            .count = size_of(.type = ErrorTraceEntry)
        )
    )
}

-- Slot headers are copied as bytes into or out of aligned local values.
-- A byte buffer (including an offset slice) need not align ErrorTraceEntry.
-- Only numeric fields are stored; no reference is reconstructed from bytes.
_error_trace_store_entry(
        .self  : $&FixedSizeErrorTracer,
        .index : UIntNative,
        .entry : ErrorTraceEntry
    ) -> () := {
    first ::= trusted_reinterpret_reference#(.from: ErrorTraceEntry, .to: UInt8)(.base = &entry).reference
    bytes ::= _trusted_array_view_ro(.data = first, .length = size_of(.type = ErrorTraceEntry))
    memcpy_bytes(.dst = _error_trace_header(self, .index = index), .src = bytes)
}

_error_trace_load_entry(
        .self  : $&FixedSizeErrorTracer,
        .index : UIntNative
    ) -> (
        .entry : ErrorTraceEntry
    ) := {
    entry = (.location = (.value = 0), .context_length = 0)
    first ::= trusted_mutable_reinterpret_reference#(.from: ErrorTraceEntry, .to: UInt8)(
        .base = $&entry
    ).reference
    bytes ::= _trusted_array_view(.data = first, .length = size_of(.type = ErrorTraceEntry))
    memcpy_bytes(.dst = bytes, .src = _error_trace_header(self, .index = index))
    -- The caller still has access to the backing bytes. Never let corrupted
    -- metadata turn one bounded slot into a read across adjacent slots.
    if entry.context_length > 128 { abort }
}

implement ErrorTracer#(FixedSizeErrorTracer)(
    .reset_context = (.self: $&FixedSizeErrorTracer) -> () {
        self&._length = 0
        self&._next = self&._capacity / 2
        self&._dropped = false
    }

    .add_context = (
            .self     : $&FixedSizeErrorTracer,
            .location : SourceLocationId,
            .context  : StringView
        ) -> () {
        assume error_tracer ::= $&noop_error_tracer

        if self&._capacity == 0 {
            self&._dropped = true
            return
        }

        index ::= self&._length

        if self&._length == self&._capacity {
            index = self&._next
            self&._dropped = true
            self&._next = self&._next + 1
            if self&._next == self&._capacity { self&._next = self&._capacity / 2 }
        } else {
            self&._length = self&._length + 1
        }

        count ::= context.length

        if count > 128 {
            count = 128
            self&._dropped = true
        }

        _error_trace_store_entry(
            self
            .index = index
            .entry = (.location = location, .context_length = count)
        )
        slot_offset ::= index * _error_trace_stride().size
        offset ::= slot_offset + size_of(.type = ErrorTraceEntry)
        i :: UIntNative = 0

        while i < count {
            byte ::= bytes_get(.view = &context, .index = i).byte
            destination ::= unwrap_or_abort(
                .value = get_rw_ref(
                    $&self&._buffer
                    .index = [
                        offset
                        + i
                    ]
                )
            )
            destination&= byte
            i = i + 1
        }
    }

    .report = (
            .self   : $&FixedSizeErrorTracer,
            .writer : $&Virtual#(.contract: Writer)
        ) -> (
            .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        ) {
        assume error_tracer ::= $&noop_error_tracer
        write_trace_text(.text = "error trace (most recent first):\n", .writer = writer)!

        if self&._length == 0 {
            write_trace_text(.text = "  <empty>\n", .writer = writer)!
        }

        first ::= self&._capacity / 2
        recent ::= self&._length

        if self&._length == self&._capacity and self&._dropped {
            i ::= self&._capacity - first
            cursor ::= self&._next
            while i > 0 {
                if cursor == first { cursor = self&._capacity }
                cursor = cursor - 1
                _error_report_entry(self, .index = cursor, .writer = writer)!
                i = i - 1
            }
            write_trace_text(.text = "  <context truncated>\n", .writer = writer)!
            recent = first
        }

        while recent > 0 {
            recent = recent - 1
            _error_report_entry(self, .index = recent, .writer = writer)!
        }

        if self&._dropped and self&._length < self&._capacity {
            write_trace_text(.text = "  <context truncated>\n", .writer = writer)!
        }

        Writer#().flush(.self = writer)!

        result = ..ok Void()
    }
)

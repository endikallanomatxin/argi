-- Source IDs index immutable executable metadata; retaining a frame does not
-- retain reader strings or references to a context expression.
SourceLocationId : Type = (.value: UInt32)
SourceLocationId implements ImplicitlyCopyable
SourceLocation : Type = (
    .source_file: &Char
    .source_line: &Char
    .line: UIntNative
    .column: UIntNative
)
SourceLocation implements ImplicitlyCopyable

-- These two core operations are lowered to executable metadata by codegen.
error_location_id() -> (.location: SourceLocationId) := {
    location = (.value = 0)
}
source_location(.id: SourceLocationId) -> (.location: SourceLocation) := {
    location = (.source_file = "", .source_line = "", .line = 0, .column = 0)
}

ErrorTracer : Abstract = (
    add_context(.self: $&Self, .location: SourceLocationId, .context: StringView) -> ()
    reset_context(.self: $&Self) -> ()
    report(.self: $&Self, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
)

-- The virtual wrapper and its receiver both have program lifetime.
NoopErrorTracer : Type = (.marker: UInt8 = 0)
NoopErrorTracer implements ErrorTracer
noop_error_tracer_storage :: NoopErrorTracer = (.marker = 0)
noop_error_tracer :: Virtual#(.abstract: ErrorTracer) = to_virtual#(.abstract: ErrorTracer)(.value = $&noop_error_tracer_storage)

add_context(.self: $&NoopErrorTracer, .location: SourceLocationId, .context: StringView) -> () := {}
reset_context(.self: $&NoopErrorTracer) -> () := {}
report(.self: $&NoopErrorTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok Void()
}

ErrorTrace : Type = (.tracer: $&Virtual#(.abstract: ErrorTracer))
ErrorTrace implements ImplicitlyCopyable
Error#(.reasons: Type) : Type = (.reason: reasons, .trace: ErrorTrace)

add_context(
    .context: StringView,
    .location: SourceLocationId = error_location_id(),
    .error_tracer: $&Virtual#(.abstract: ErrorTracer) = reach error_tracer,
) -> () := {
    add_context(.self = error_tracer, .location = location, .context = context)
}
add_context(
    .context: &Char,
    .location: SourceLocationId = error_location_id(),
    .error_tracer: $&Virtual#(.abstract: ErrorTracer) = reach error_tracer,
) -> () := {
    add_context(.self = error_tracer, .location = location, .context = c_string_as_view(.text = context).view)
}

create_error_trace(
    .location: SourceLocationId,
    .error_tracer: $&Virtual#(.abstract: ErrorTracer) = reach error_tracer,
) -> (.trace: ErrorTrace) := {
    add_context(.context = "", .location = location, .error_tracer = error_tracer)
    trace = (.tracer = error_tracer)
}
-- Propagation binds the original capability explicitly. The text/view
-- overloads keep length-delimited views separate from zero-terminated text.
_add_error_context(.trace: ErrorTrace, .location: SourceLocationId, .context: StringView) -> () := {
    add_context(.context = context, .location = location, .error_tracer = trace.tracer)
}
_add_error_context_text(.trace: ErrorTrace, .location: SourceLocationId, .context: &Char) -> () := {
    add_context(.context = context, .location = location, .error_tracer = trace.tracer)
}

ErrorTraceEntry : Type = (.location: SourceLocationId, .context_length: UIntNative)
ErrorTraceEntry implements ImplicitlyCopyable

-- Fixed slots bound both context copy work and memory use. The first half
-- retains early frames; the second half replaces recent frames in a ring.
-- All errors referring to this tracer share the same diagnostic log.
FixedSizeErrorTracer : Type = (
    ._buffer: ArrayView#(.t: UInt8)
    ._capacity: UIntNative
    ._length: UIntNative
    ._next: UIntNative
    ._dropped: Bool
)
FixedSizeErrorTracer implements ErrorTracer

_error_trace_stride() -> (.size: UIntNative) := {
    size = size_of(.type = ErrorTraceEntry) + 128
}
-- The buffer is initialized caller-owned storage, not an allocation owned by
-- the tracer. Trailing bytes that do not fit a complete slot are unused.
FixedSizeErrorTracer init(.buffer: ArrayView#(.t: UInt8)) -> (.result: FixedSizeErrorTracer) := {
    capacity ::= length(.self = &buffer).count / _error_trace_stride().size
    result = (
        ._buffer = buffer,
        ._capacity = capacity,
        ._length = 0,
        ._next = capacity / 2,
        ._dropped = false,
    )
}
-- Ending the tracer invalidates its handles without releasing caller storage.
deinit(.self: $&FixedSizeErrorTracer) -> () := {}
reset_context(.self: $&FixedSizeErrorTracer) -> () := {
    self&._length = 0
    self&._next = self&._capacity / 2
    self&._dropped = false
}
_error_trace_header(.self: $&FixedSizeErrorTracer, .index: UIntNative) -> (.header: ArrayView#(.t: UInt8)) := {
    assume error_tracer ::= $&noop_error_tracer
    if index >= self&._capacity { abort }
    header = unwrap_or_abort(.value = slice(
        .self = &self&._buffer,
        .start = index * _error_trace_stride().size,
        .count = size_of(.type = ErrorTraceEntry),
    ))
}

-- Slot headers are copied as bytes into or out of aligned local values.
-- A byte buffer (including an offset slice) need not align ErrorTraceEntry.
-- Only numeric fields are stored; no reference is reconstructed from bytes.
_error_trace_store_entry(.self: $&FixedSizeErrorTracer, .index: UIntNative, .entry: ErrorTraceEntry) -> () := {
    first ::= trusted_reinterpret_reference#(.from: ErrorTraceEntry, .to: UInt8)(.base = &entry).reference
    bytes ::= _trusted_array_view_ro(.data = first, .length = size_of(.type = ErrorTraceEntry))
    memcpy_bytes(.dst = _error_trace_header(.self = self, .index = index), .src = bytes)
}
_error_trace_load_entry(.self: $&FixedSizeErrorTracer, .index: UIntNative) -> (.entry: ErrorTraceEntry) := {
    entry = (.location = (.value = 0), .context_length = 0)
    first ::= trusted_mutable_reinterpret_reference#(.from: ErrorTraceEntry, .to: UInt8)(.base = $&entry).reference
    bytes ::= _trusted_array_view(.data = first, .length = size_of(.type = ErrorTraceEntry))
    memcpy_bytes(.dst = bytes, .src = _error_trace_header(.self = self, .index = index))
    -- The caller still has access to the backing bytes. Never let corrupted
    -- metadata turn one bounded slot into a read across adjacent slots.
    if entry.context_length > 128 { abort }
}
add_context(.self: $&FixedSizeErrorTracer, .location: SourceLocationId, .context: StringView) -> () := {
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
    _error_trace_store_entry(.self = self, .index = index, .entry = (.location = location, .context_length = count))
    slot_offset ::= index * _error_trace_stride().size
    offset ::= slot_offset + size_of(.type = ErrorTraceEntry)
    i :: UIntNative = 0
    while i < count {
        byte ::= bytes_get(.view = &context, .index = i).byte
        destination ::= unwrap_or_abort(.value = get_rw_ref(.self = $&self&._buffer, .index = offset + i))
        destination& = byte
        i = i + 1
    }
}

write_trace_text(.text: &Char, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    view ::= c_string_as_view(.text = text).view
    i :: UIntNative = 0
    while i < view.length {
        write_byte(.self = writer, .byte = bytes_get(.view = &view, .index = i).byte)!
        i = i + 1
    }
    result = ..ok Void()
}
write_trace_uint(.value: UIntNative, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    divisor :: UIntNative = 1
    while divisor <= value / 10 { divisor = divisor * 10 }
    remaining ::= value
    digits :: StringView = "0123456789"
    while divisor > 0 {
        digit ::= remaining / divisor
        remaining = remaining % divisor
        write_byte(.self = writer, .byte = bytes_get(.view = &digits, .index = digit).byte)!
        divisor = divisor / 10
    }
    result = ..ok Void()
}
_error_report_entry(.self: $&FixedSizeErrorTracer, .index: UIntNative, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    entry ::= _error_trace_load_entry(.self = self, .index = index)
    location ::= source_location(.id = entry.location).location
    write_trace_text(.text = "  at ", .writer = writer)!
    write_trace_text(.text = location.source_file, .writer = writer)!
    write_trace_text(.text = ":", .writer = writer)!
    write_trace_uint(.value = location.line, .writer = writer)!
    write_trace_text(.text = ":", .writer = writer)!
    write_trace_uint(.value = location.column, .writer = writer)!
    slot_offset ::= index * _error_trace_stride().size
    offset ::= slot_offset + size_of(.type = ErrorTraceEntry)
    if entry.context_length != 0 {
        write_trace_text(.text = ": ", .writer = writer)!
        i :: UIntNative = 0
        while i < entry.context_length {
            byte ::= unwrap_or_abort(.value = get(.self = &self&._buffer, .index = offset + i))
            write_byte(.self = writer, .byte = byte)!
            i = i + 1
        }
    }
    write_trace_text(.text = "\n    ", .writer = writer)!
    write_trace_text(.text = location.source_line, .writer = writer)!
    write_trace_text(.text = "\n    ", .writer = writer)!
    column :: UIntNative = 1
    while column < location.column {
        write_byte(.self = writer, .byte = 32)!
        column = column + 1
    }
    write_trace_text(.text = "^\n", .writer = writer)!
    result = ..ok Void()
}
report(.self: $&FixedSizeErrorTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
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
            _error_report_entry(.self = self, .index = cursor, .writer = writer)!
            i = i - 1
        }
        write_trace_text(.text = "  <context truncated>\n", .writer = writer)!
        recent = first
    }
    while recent > 0 {
        recent = recent - 1
        _error_report_entry(.self = self, .index = recent, .writer = writer)!
    }
    if self&._dropped and self&._length < self&._capacity {
        write_trace_text(.text = "  <context truncated>\n", .writer = writer)!
    }
    flush(.self = writer)!
    result = ..ok Void()
}
report_trace(.trace: &ErrorTrace, .writer: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    virtual_writer ::= to_virtual#(.abstract: Writer)(.value = writer)
    report(.self = trace&.tracer, .writer = $&virtual_writer)!
    result = ..ok Void()
}
report_error#(.reasons: Type)(.err: &Error#(.reasons: reasons), .writer: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    report_trace(.trace = &err&.trace, .writer = writer)!
    result = ..ok Void()
}
report_error#(.reasons: Type)(.message: &Char, .err: &Error#(.reasons: reasons), .writer: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    virtual_writer ::= to_virtual#(.abstract: Writer)(.value = writer)
    write_trace_text(.text = "error: ", .writer = $&virtual_writer)!
    write_trace_text(.text = message, .writer = $&virtual_writer)!
    write_trace_text(.text = "\n", .writer = $&virtual_writer)!
    report_trace(.trace = &err&.trace, .writer = writer)!
    result = ..ok Void()
}

Errable #(.t: Type, .reasons: Type) : Type = (
    ..ok t
    ..error Error#(.reasons = reasons)
)

unwrap_or_abort#(.t: Type, .reasons: Type)(.value: Errable#(.t: t, .reasons: reasons)) -> (.result: t) := {
    match value {
        ..ok ~ payload { result = ~payload }
        ..error _ { abort }
    }
}

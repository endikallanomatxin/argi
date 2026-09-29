-- Source IDs index immutable executable metadata; retaining a frame does not
-- retain source strings or references to a context expression.
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
    report(.self: $&Self, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
)

-- The virtual wrapper and its receiver both have program lifetime.
NoopErrorTracer : Type = (.marker: UInt8 = 0)
NoopErrorTracer implements ErrorTracer
noop_error_tracer_storage :: NoopErrorTracer = (.marker = 0)
noop_error_tracer :: Virtual#(.abstract: ErrorTracer) = to_virtual#(.abstract: ErrorTracer)(.value = $&noop_error_tracer_storage)

add_context(.self: $&NoopErrorTracer, .location: SourceLocationId, .context: StringView) -> () := {}
reset_context(.self: $&NoopErrorTracer) -> () := {}
report(.self: $&NoopErrorTracer, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
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
    ._storage: Allocation
    ._capacity: UIntNative
    ._length: UIntNative
    ._next: UIntNative
    ._dropped: Bool
)
FixedSizeErrorTracer implements ErrorTracer

_error_trace_stride() -> (.size: UIntNative) := {
    size = size_of(.type = ErrorTraceEntry) + 128
}
_error_trace_alignment() -> (.alignment: UIntNative) := {
    alignment = alignment_of(.type = ErrorTraceEntry)
}
init(.p: $&FixedSizeErrorTracer, .allocator: $&Allocator, .size: UIntNative = 65536) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    storage ::= allocate(.self = allocator, .size = size, .alignment = _error_trace_alignment().alignment)!
    p&._storage = ~storage
    p&._capacity = size / _error_trace_stride().size
    p&._length = 0
    p&._next = p&._capacity / 2
    p&._dropped = false
    result = ..ok Void()
}
deinit(.self: $&FixedSizeErrorTracer) -> () := { deinit(.self = $&self&._storage) }
reset_context(.self: $&FixedSizeErrorTracer) -> () := {
    self&._length = 0
    self&._next = self&._capacity / 2
    self&._dropped = false
}
_trusted_error_trace_slot(.self: $&FixedSizeErrorTracer, .index: UIntNative) -> (.entry: $&ErrorTraceEntry) := {
    if index >= self&._capacity {
        abort
    }
    raw ::= raw_pointer#(.t: ErrorTraceEntry)(.address = self&._storage.data.address + index * _error_trace_stride().size).raw
    entry = establish_allocation_slot#(.t: ErrorTraceEntry)(.allocation = &self&._storage, .slot = raw, .anchor = self&._storage.anchor).reference
}
add_context(.self: $&FixedSizeErrorTracer, .location: SourceLocationId, .context: StringView) -> () := {
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
    entry ::= _trusted_error_trace_slot(.self = self, .index = index).entry
    entry& = (.location = location, .context_length = count)
    offset ::= index * _error_trace_stride().size + size_of(.type = ErrorTraceEntry)
    i :: UIntNative = 0
    while i < count {
        byte ::= bytes_get(.view = &context, .index = i).byte
        destination ::= _trusted_allocation_byte_rw(.allocation = $&self&._storage, .offset = offset + i).reference
        destination& = byte
        i = i + 1
    }
}

write_trace_text(.text: &Char, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    view ::= c_string_as_view(.text = text).view
    i :: UIntNative = 0
    while i < view.length {
        write_byte(.self = stderr, .byte = bytes_get(.view = &view, .index = i).byte)!
        i = i + 1
    }
    result = ..ok Void()
}
write_trace_uint(.value: UIntNative, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    divisor :: UIntNative = 1
    while divisor <= value / 10 { divisor = divisor * 10 }
    remaining ::= value
    digits :: StringView = "0123456789"
    while divisor > 0 {
        digit ::= remaining / divisor
        remaining = remaining % divisor
        write_byte(.self = stderr, .byte = bytes_get(.view = &digits, .index = digit).byte)!
        divisor = divisor / 10
    }
    result = ..ok Void()
}
_error_report_entry(.self: $&FixedSizeErrorTracer, .index: UIntNative, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    entry ::= _trusted_error_trace_slot(.self = self, .index = index).entry
    location ::= source_location(.id = entry&.location).location
    write_trace_text(.text = "  at ", .stderr = stderr)!
    write_trace_text(.text = location.source_file, .stderr = stderr)!
    write_trace_text(.text = ":", .stderr = stderr)!
    write_trace_uint(.value = location.line, .stderr = stderr)!
    write_trace_text(.text = ":", .stderr = stderr)!
    write_trace_uint(.value = location.column, .stderr = stderr)!
    offset ::= index * _error_trace_stride().size + size_of(.type = ErrorTraceEntry)
    if entry&.context_length != 0 {
        write_trace_text(.text = ": ", .stderr = stderr)!
        i :: UIntNative = 0
        while i < entry&.context_length {
            byte ::= _trusted_allocation_byte_ro(.allocation = &self&._storage, .offset = offset + i).reference&
            write_byte(.self = stderr, .byte = byte)!
            i = i + 1
        }
    }
    write_trace_text(.text = "\n    ", .stderr = stderr)!
    write_trace_text(.text = location.source_line, .stderr = stderr)!
    write_trace_text(.text = "\n    ", .stderr = stderr)!
    column :: UIntNative = 1
    while column < location.column {
        write_byte(.self = stderr, .byte = 32)!
        column = column + 1
    }
    write_trace_text(.text = "^\n", .stderr = stderr)!
    result = ..ok Void()
}
report(.self: $&FixedSizeErrorTracer, .stderr: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    write_trace_text(.text = "error trace (most recent first):\n", .stderr = stderr)!
    if self&._length == 0 {
        write_trace_text(.text = "  <empty>\n", .stderr = stderr)!
    }
    first ::= self&._capacity / 2
    recent ::= self&._length
    if self&._length == self&._capacity and self&._dropped {
        i ::= self&._capacity - first
        cursor ::= self&._next
        while i > 0 {
            if cursor == first { cursor = self&._capacity }
            cursor = cursor - 1
            _error_report_entry(.self = self, .index = cursor, .stderr = stderr)!
            i = i - 1
        }
        write_trace_text(.text = "  <context truncated>\n", .stderr = stderr)!
        recent = first
    }
    while recent > 0 {
        recent = recent - 1
        _error_report_entry(.self = self, .index = recent, .stderr = stderr)!
    }
    if self&._dropped and self&._length < self&._capacity {
        write_trace_text(.text = "  <context truncated>\n", .stderr = stderr)!
    }
    flush(.self = stderr)!
    result = ..ok Void()
}
report_trace(.trace: &ErrorTrace, .stderr: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    writer ::= to_virtual#(.abstract: Writer)(.value = stderr)
    report(.self = trace&.tracer, .stderr = $&writer)!
    result = ..ok Void()
}
report_error#(.reasons: Type)(.err: &Error#(.reasons: reasons), .stderr: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    report_trace(.trace = &err&.trace, .stderr = stderr)!
    result = ..ok Void()
}
report_error#(.reasons: Type)(.message: &Char, .err: &Error#(.reasons: reasons), .stderr: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    writer ::= to_virtual#(.abstract: Writer)(.value = stderr)
    write_trace_text(.text = "error: ", .stderr = $&writer)!
    write_trace_text(.text = message, .stderr = $&writer)!
    write_trace_text(.text = "\n", .stderr = $&writer)!
    report_trace(.trace = &err&.trace, .stderr = stderr)!
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

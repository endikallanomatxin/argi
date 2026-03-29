ErrorTraceEntry : Type = (
    .line: UIntNative
    .column: UIntNative
    .context: &Char
    .source_line: &Char
    .source_file: &Char
)

ErrorTrace : Type = (
    .entries: DynamicArray#(.t: ErrorTraceEntry)
)

Error#(.reason: Type) : Type = (
    .reason: reason
    .trace: ErrorTrace
)

write_trace_text(
    .text: &Char,
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    i :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = text) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }

        write_byte(.self = stderr, .byte = ptr&)
        i = i + 1
    }
}

write_trace_uint(
    .value: UIntNative,
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    if value == 0 {
        write_trace_text(.text = "0", .stderr = stderr)
        return
    }

    divisor :: UIntNative = 1
    while divisor <= value / 10 {
        divisor = divisor * 10
    }

    remaining :: UIntNative = value
    while divisor > 0 {
        digit := remaining / divisor
        remaining = remaining % divisor

        if digit == 0 {
            write_trace_text(.text = "0", .stderr = stderr)
        }
        if digit == 1 {
            write_trace_text(.text = "1", .stderr = stderr)
        }
        if digit == 2 {
            write_trace_text(.text = "2", .stderr = stderr)
        }
        if digit == 3 {
            write_trace_text(.text = "3", .stderr = stderr)
        }
        if digit == 4 {
            write_trace_text(.text = "4", .stderr = stderr)
        }
        if digit == 5 {
            write_trace_text(.text = "5", .stderr = stderr)
        }
        if digit == 6 {
            write_trace_text(.text = "6", .stderr = stderr)
        }
        if digit == 7 {
            write_trace_text(.text = "7", .stderr = stderr)
        }
        if digit == 8 {
            write_trace_text(.text = "8", .stderr = stderr)
        }
        if digit == 9 {
            write_trace_text(.text = "9", .stderr = stderr)
        }

        divisor = divisor / 10
    }
}

write_trace_spaces(
    .count: UIntNative,
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    i :: UIntNative = 0
    while i < count {
        write_byte(.self = stderr, .byte = 32)
        i = i + 1
    }
}

report_trace(
    .trace: &ErrorTrace,
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    write_trace_text(.text = "error trace (most recent first):\n", .stderr = stderr)

    if trace&.entries.length == 0 {
        write_trace_text(.text = "  <empty>\n", .stderr = stderr)
        flush(.self = stderr)
        return
    }

    i ::= trace&.entries.length
    while i > 0 {
        entry := trace&.entries[i - 1]
        write_trace_text(.text = "  at ", .stderr = stderr)
        write_trace_text(.text = entry.source_file, .stderr = stderr)
        write_byte(.self = stderr, .byte = 58)
        write_trace_uint(.value = entry.line, .stderr = stderr)
        write_byte(.self = stderr, .byte = 58)
        write_trace_uint(.value = entry.column, .stderr = stderr)

        if cast#(.to: UIntNative)(.value = entry.context) != 0 {
            write_trace_text(.text = ": ", .stderr = stderr)
            write_trace_text(.text = entry.context, .stderr = stderr)
        }

        write_byte(.self = stderr, .byte = 10)

        if cast#(.to: UIntNative)(.value = entry.source_line) != 0 {
            write_trace_text(.text = "    ", .stderr = stderr)
            write_trace_text(.text = entry.source_line, .stderr = stderr)
            write_byte(.self = stderr, .byte = 10)
            write_trace_text(.text = "    ", .stderr = stderr)

            if entry.column > 1 {
                write_trace_spaces(.count = entry.column - 1, .stderr = stderr)
            }

            write_byte(.self = stderr, .byte = 94)
            write_byte(.self = stderr, .byte = 10)
        }

        i = i - 1
    }

    flush(.self = stderr)
}

Errable #(.t: Type, .reason: Type) : Type = (
    ..ok(.value: t)
    ..error(
        .reason: reason
        .trace: ErrorTrace
    )
)

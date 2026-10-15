p := import ("python")

..invalid_arguments
..invalid_duration

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    output ::= $&BufferedWriter(
        $&system.terminal&.stdout
        view($&zeroed#([4096]UInt8)())
    )
    #defer {
        Writer#().flush(output) handle error {
            status_code = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        }
    }

    argc ::= length(system.args).count
    if argc < 2 or argc > 3 {
        print("Usage: csv-report <file.csv> [duration-column]", .writer = output)!!! { status_code = 1 }
        invalid_arguments()!!! { status_code = 1 }
        return
    }

    path ::= argument_view_at(system.args, 1)
    column ::= "duration_ms"
    if argc == 3 { column = argument_view_at(system.args, 2) }

    file_reader ::= File(.file_system = system.file_system, .path = path, .mode = ..read) handle error, value {
        add_context(.context = path, .error_tracer = error.tracer)
        report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        status_code = 1
        return
    }
    text ::= read_all_limited($&file_reader, view($&zeroed#([8192]UInt8)()), 1048576) handle error, value {
        add_context(.context = path, .error_tracer = error.tracer)
        report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        status_code = 1
        return
    }
    close($&file_reader) handle error, value {
        add_context(.context = path, .error_tracer = error.tracer)
        report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        status_code = 1
        return
    }

    interpreter ::= p.Python(system.ffi)!!! { status_code = 1 }
    #defer {
        print_python_error(&interpreter, $&system.terminal&.stderr, allocator) handle error {
            status_code = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        }
    }

    io ::= p.import_module(&interpreter, "io")!!! { status_code = 1 }
    csv ::= p.import_module(&interpreter, "csv")!!! { status_code = 1 }
    builtins ::= p.import_module(&interpreter, "builtins")!!! { status_code = 1 }
    statistics ::= p.import_module(&interpreter, "statistics")!!! { status_code = 1 }

    source ::= p.string(&interpreter, as_view(&text))!!! { status_code = 1 }
    stream ::= p.call_method(&io, "StringIO", .arguments = view(&(&source)))!!! { status_code = 1 }
    rows ::= p.call_method(&csv, "DictReader", .arguments = view(&(&stream)))!!! { status_code = 1 }
    column_key ::= p.string(&interpreter, column)!!! { status_code = 1 }
    samples ::= p.list(&interpreter)!!! { status_code = 1 }
    iterator ::= p.iterate(&rows)!!! { status_code = 1 }

    while true {
        match [p.next($&iterator)!!! { status_code = 1 }] {
            ..none { break }
            ..some ~entry {
                cell ::= p.get_item(&entry.value, &column_key)!!! { status_code = 1 }
                cell_text ::= p.to_string(&cell)!!! { status_code = 1 }
                duration ::= parse_float64(as_view(&cell_text))!!! { status_code = 1 }
                sample ::= p.floating(&interpreter, duration)!!! { status_code = 1 }
                if is_finite(.value = duration).ok == false or duration < 0.0 {
                    invalid_duration()!!! { status_code = 1 }
                    return
                }
                p.append(&samples, &sample)!!! { status_code = 1 }
            }
        }
    }

    count ::= p.length(&samples)!!! { status_code = 1 }
    mean ::= p.call_method(&statistics, "fmean", .arguments = view(&(&samples)))!!! { status_code = 1 }
    median ::= p.call_method(&statistics, "median", .arguments = view(&(&samples)))!!! { status_code = 1 }
    precision ::= p.string(&interpreter, ".2f")!!! { status_code = 1 }
    mean_text ::= p.call_method(&builtins, "format", .arguments = view(&(&mean, &precision)))!!! { status_code = 1 }
    median_text ::= p.call_method(
        &builtins
        "format"
        .arguments = view(&(&median, &precision))
    )!!! { status_code = 1 }
    mean_result ::= p.to_string(&mean_text)!!! { status_code = 1 }
    median_result ::= p.to_string(&median_text)!!! { status_code = 1 }

    print("requests", .terminator = "\t", .writer = output)!!! { status_code = 1 }
    print(count, .writer = output)!!! { status_code = 1 }
    print("mean_ms", .terminator = "\t", .writer = output)!!! { status_code = 1 }
    print(as_view(&mean_result), .writer = output)!!! { status_code = 1 }
    print("median_ms", .terminator = "\t", .writer = output)!!! { status_code = 1 }
    print(as_view(&median_result), .writer = output)!!! { status_code = 1 }
}

print_python_error(
        .interpreter : &p.Python,
        .writer      : $&File,
        .allocator   : $&PageAllocator
    ) -> !Void = ..ok Void() := {
    assume allocator
    assume writer

    message ::= p.error_text(interpreter)!
    message_view ::= as_view(&message)
    if message_view != "" { print(message_view)! }
}

invalid_arguments() -> (.result: Errable#(Void, (..invalid_arguments))) := {
    result = ..error(.reason = ..invalid_arguments)
}

invalid_duration() -> (.result: Errable#(Void, (..invalid_duration))) := {
    result = ..error(.reason = ..invalid_duration)
}

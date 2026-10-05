p := import ("python")

..invalid_arguments
..invalid_duration

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume writer ::= $&BufferedWriter(
        $&system.terminal&.stdout
        view($&zeroed#([4096]UInt8)())
    )
    #defer flush(writer)!

    argc ::= length(system.args).count
    if argc < 2 or argc > 3 {
        print("Usage: csv-report <file.csv> [duration-column]")!
        invalid_arguments()!
        return
    }

    path ::= argument_view_at(system.args, 1)
    column ::= "duration_ms"
    if argc == 3 { column = argument_view_at(system.args, 2) }

    file_reader ::= open_read(system.file_system, path)!! path
    text ::= read_all_limited($&file_reader, view($&zeroed#([8192]UInt8)()), 1048576)!! path
    close($&file_reader)!! path

    interpreter ::= p.Python(system.ffi)!
    #defer print_python_error(&interpreter, $&system.terminal&.stderr, allocator)!

    io ::= p.import_module(&interpreter, "io")!
    csv ::= p.import_module(&interpreter, "csv")!
    builtins ::= p.import_module(&interpreter, "builtins")!
    statistics ::= p.import_module(&interpreter, "statistics")!

    source ::= p.string(&interpreter, as_view(&text))!
    stream ::= p.call_method(&io, "StringIO", .arguments = view(&(&source)))!
    rows ::= p.call_method(&csv, "DictReader", .arguments = view(&(&stream)))!
    column_key ::= p.string(&interpreter, column)!
    samples ::= p.list(&interpreter)!
    iterator ::= p.iterate(&rows)!

    while true {
        match p.next($&iterator)! {
            ..none { break }
            ..some ~entry {
                cell ::= p.get_item(&entry.value, &column_key)!
                cell_text ::= p.to_string(&cell)!
                duration ::= parse_float64(as_view(&cell_text))!
                sample ::= p.floating(&interpreter, duration)!
                if is_finite(.value = duration).ok == false or duration < 0.0 {
                    invalid_duration()!
                    return
                }
                p.append(&samples, &sample)!
            }
        }
    }

    count ::= p.length(&samples)!
    mean ::= p.call_method(&statistics, "fmean", .arguments = view(&(&samples)))!
    median ::= p.call_method(&statistics, "median", .arguments = view(&(&samples)))!
    precision ::= p.string(&interpreter, ".2f")!
    mean_text ::= p.call_method(&builtins, "format", .arguments = view(&(&mean, &precision)))!
    median_text ::= p.call_method(
        &builtins
        "format"
        .arguments = view(&(&median, &precision))
    )!
    mean_result ::= p.to_string(&mean_text)!
    median_result ::= p.to_string(&median_text)!

    print("requests", .terminator = "\t")!
    print(count)!
    print("mean_ms", .terminator = "\t")!
    print(as_view(&mean_result))!
    print("median_ms", .terminator = "\t")!
    print(as_view(&median_result))!
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

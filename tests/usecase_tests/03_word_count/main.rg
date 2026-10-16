words ::= import ("./library")

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    output ::= $&BufferedWriter($&system.terminal&.stdout, view($&zeroed#([8192]UInt8)()))
    #defer {
        Writer#().flush(output) handle error {
            status_code = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        }
    }

    argc ::= length(system.args).count
    if argc < 2 or argc > 3 {
        print("Usage: word-count <directory> [maximum-file-bytes]", .writer = output)!!! {
            status_code = 1
        }
        return
    }

    limit :: UIntNative = 1048576
    if argc == 3 {
        limit = parse_uintnative(unwrap_or_abort(.value = argument_view_at(system.args, 2)))!!! {
            status_code = 1
        }
    }

    counts ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        StringHashPolicy()
    )!!! { status_code = 1 }
    words.count_directory(
        $&counts
        unwrap_or_abort(.value = argument_view_at(system.args, 1))
        limit
        view($&zeroed#([8192]UInt8)())
    )!!! { status_code = 1 }

    for entry in counts {
        print(entry.value&, .terminator = "\t", .writer = output)!!! { status_code = 1 }
        print(view(entry.key), .writer = output)!!! { status_code = 1 }
    }
}

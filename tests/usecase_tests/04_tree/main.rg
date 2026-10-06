-- A small consumer of declarative options, owned paths and directory walking.
run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    assume writer ::= $&system.terminal&.stdout

    specs ::= (
        CliSpec("help", "h", "Show help"),
        CliSpec(
            "root"
            "r"
            "Directory to visit"
            .value_name = "PATH"
            .required   = true
        ),
        CliSpec(
            "depth"
            "d"
            "Maximum depth"
            .value_name    = "N"
            .default_value = ..some(.value = "64")
        )
    )

    if length(system.args).count == 2 {
        argument ::= argument_view_at(system.args, 1)
        if argument == "--help" or argument == "-h" {
            write_cli_help(
                .program = "tree"
                .about   = "List directory entries"
                .specs   = view(&specs)
            )!
            return
        }
    }

    parsed ::= parse_cli(
        .source = system.args
        .specs  = view(&specs)
        .start  = 1
    )!

    root ::= "."
    maximum_depth :: UIntNative = 64
    for option in parsed.options {
        match option.value {
            ..none {}
            ..some entry {
                if option.name == "root" { root = entry.value }
                if option.name == "depth" { maximum_depth = parse_uintnative(entry.value)! }
            }
        }
    }

    walker ::= DirectoryWalker(
        .path          = root
        .maximum_depth = maximum_depth
    )!

    while true {
        match next($&walker)! {
            ..none { break }
            ..some ~entry {
                print(as_view(&entry.value.path))!
            }
        }
    }

    flush()!
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}

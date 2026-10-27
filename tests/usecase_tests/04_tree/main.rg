-- A small consumer of declarative options, owned paths and directory walking.
main := (.system: System) -> (.status_code: Int32 = 0)  {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    output ::= $&system.terminal&.stdout

    specs ::= (
        CliSpec("help", "h", "Show help"),
        CliSpec("root", "r", "Directory to visit", .value_name = "PATH", .required = true),
        CliSpec(
            "depth"
            "d"
            "Maximum depth"
            .value_name    = "N"
            .default_value = ..some(.value = "64")
        )
    )

    if length(system.args).count == 2 {
        argument ::= unwrap_or_abort(.value = argument_view_at(system.args, 1))
        if argument == "--help" or argument == "-h" {
            write_cli_help(
                .program = "tree"
                .about   = "List directory entries"
                .specs   = view(&specs)
                .writer  = output
            )!!! { status_code = 1 }
            return
        }
    }

    parsed ::= parse_cli(.source = system.args, .specs = view(&specs), .start = 1)!!! {
        status_code = 1
    }

    root ::= "."
    maximum_depth :: UIntNative = 64
    for option in parsed.options {
        match option.value {
            ..none {}
            ..some entry {
                if option.name == "root" { root = entry.value }
                if option.name == "depth" {
                    maximum_depth = parse_uintnative(entry.value)!!! { status_code = 1 }
                }
            }
        }
    }

    walker ::= DirectoryWalker(.path = root, .maximum_depth = maximum_depth)!!! {
        status_code = 1
    }

    while true {
        match [next($&walker)!!! { status_code = 1 }] {
            ..none { break }
            ..some ~entry {
                print(view(&entry.value.path), .writer = output)!!! { status_code = 1 }
            }
        }
    }

    Writer#().flush(output)!!! { status_code = 1 }
}

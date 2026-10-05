-- A small consumer of declarative options, owned paths and directory walking.
main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    specs :: [3]CliSpec = (
        CliSpec(.name = "help", .short_name = "h", .help = "Show help"),
        CliSpec(
            .name       = "root"
            .short_name = "r"
            .value_name = "PATH"
            .required   = true
            .help       = "Directory to visit"
        ),
        CliSpec(
            .name          = "depth"
            .short_name    = "d"
            .value_name    = "N"
            .default_value = ..some(.value = "64")
            .help          = "Maximum depth"
        )
    )
    out ::= $&system.terminal&.stdout
    if length(.self = system.args).count == 2 {
        argument ::= argument_view_at(.self = system.args, .index = 1)
        if argument == "--help" or argument == "-h" {
            write_cli_help(
                .writer  = out
                .program = "tree"
                .about   = "List directory entries"
                .specs   = view(.array = &specs)
            )!
            return
        }
    }
    parsed ::= parse_cli(
        .source    = system.args
        .specs     = view(.array = &specs)
        .start     = 1
        .allocator = allocator
    )!
    root :: StringView = "."
    maximum :: UIntNative = 64
    for option in parsed.options {
        match option.value {
            ..none {}
            ..some entry {
                if option.name == "root" { root = entry.value }
                if option.name == "depth" { maximum = parse_uintnative(.text = entry.value)! }
            }
        }
    }
    walker ::= DirectoryWalker(
        .self          = system.file_sys
        .path          = root
        .maximum_depth = maximum
        .allocator     = allocator
    )!
    while true {
        match next(.self = $&walker, .allocator = allocator)! {
            ..none { break }
            ..some ~entry {
                write(.self = out, .text = as_view(.self = &entry.value.path))!
                write(.self = out, .text = "\n")!
            }
        }
    }
    flush(.self = out)!
}

run_main(.system: System) -> (.result: Errable#(.t: Void, .reasons: CliReasons) = ..ok Void()) := {
    assume allocator := system.page_allocator
    specs :: [3]CliSpec = (
        CliSpec(.name = "verbose", .short_name = "v", .help = "Enable tracing", .repeatable = true),
        CliSpec(
            .name       = "output"
            .short_name = "o"
            .help       = "Output file"
            .value_name = "FILE"
            .required   = true
        ),
        CliSpec(.name = "count", .value_name = "N", .default_value = ..some(.value = "10"))
    )
    args :: [4]StringView = ("-vv", "-o=result", "input", "--")
    source ::= CliArgumentViews(.values = view(.array = &args))
    parsed ::= parse_cli#(.t: CliArgumentViews)(
        .source    = &source
        .specs     = view(.array = &specs)
        .allocator = allocator
    )!
    if length(.self = &parsed.options).count != 4 { abort }
    if length(.self = &parsed.positionals).count != 1 { abort }
    output ::= unwrap_or_abort(.value = get(.self = &parsed.options, .index = 2))
    match output.value { ..none { abort } ..some entry { if entry.value != "result" { abort } } }
    empty :: [0]StringView = ()
    empty_source ::= CliArgumentViews(.values = view(.array = &empty))
    match parse_cli#(.t: CliArgumentViews)(
        .source    = &empty_source
        .specs     = view(.array = &specs)
        .allocator = allocator
    ) { ..ok ~_ { abort } ..error&err { if [
                err&.reason
                != ..required_option
            ] { abort } } }
    bad :: [1]StringView = ("--unknown")
    bad_source ::= CliArgumentViews(.values = view(.array = &bad))
    match parse_cli#(.t: CliArgumentViews)(
        .source    = &bad_source
        .specs     = view(.array = &specs)
        .allocator = allocator
    ) {
        ..ok ~_ { abort } ..error&err { if [
                err&.reason
                != ..unknown_option
            ] { abort } }
    }
    duplicate :: [2]StringView = ("--output=a", "--output=b")
    duplicate_source ::= CliArgumentViews(.values = view(.array = &duplicate))
    match parse_cli#(.t: CliArgumentViews)(
        .source    = &duplicate_source
        .specs     = view(.array = &specs)
        .allocator = allocator
    ) { ..ok ~_ { abort } ..error&err { if [
                err&.reason
                != ..duplicate_option
            ] { abort } } }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}

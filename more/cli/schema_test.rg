test cli_schema_validation := (.system: System) -> !() {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    specs :: [3]Spec = (
        Spec(.name = "verbose", .short_name = "v", .help = "Enable tracing", .repeatable = true),
        Spec(
            .name       = "output"
            .short_name = "o"
            .help       = "Output file"
            .value_name = "FILE"
            .required   = true
        ), Spec(.name = "count", .value_name = "N", .default_value = ..some(.value = "10"))
    )
    args :: [4]StringView = ("-vv", "-o=result", "input", "--")
    source ::= ArgumentViews(.values = view(.self = &args))
    parsed ::= parse#(.t: ArgumentViews)(
        .source = &source, .specs = view(.self = &specs), .allocator = allocator
    )!
    if length(.self = &parsed.options).count != 4 { abort }
    if length(.self = &parsed.positionals).count != 1 { abort }
    output ::= get(.self = &parsed.options, .index = 2)!
    match output.value {
        ..none { abort } ..some entry { if entry.value != "result" { abort } }
    }
    empty :: [0]StringView = ()
    empty_source ::= ArgumentViews(.values = view(.self = &empty))
    match parse#(.t: ArgumentViews)(
        .source = &empty_source, .specs = view(.self = &specs), .allocator = allocator
    ) { ..ok ~_ { abort } ..error&err { if [err&.reason != ..required_option] { abort } } }
    bad :: [1]StringView = ("--unknown")
    bad_source ::= ArgumentViews(.values = view(.self = &bad))
    match parse#(.t: ArgumentViews)(
        .source = &bad_source, .specs = view(.self = &specs), .allocator = allocator
    ) {
        ..ok ~_ { abort } ..error&err { if [err&.reason != ..unknown_option] { abort } }
    }
    duplicate :: [2]StringView = ("--output=a", "--output=b")
    duplicate_source ::= ArgumentViews(.values = view(.self = &duplicate))
    match parse#(.t: ArgumentViews)(
        .source = &duplicate_source, .specs = view(.self = &specs), .allocator = allocator
    ) { ..ok ~_ { abort } ..error&err { if [err&.reason != ..duplicate_option] { abort } } }
    invalid :: [4]Spec = (
        Spec(.name = "bad\tname"), Spec(.name = "bad\nname"),
        Spec(.name = "alias", .short_name = "="),
        Spec(.name = "flag", .default_value = ..some(.value = "true"))
    )
    for spec in invalid {
        schema :: [1]Spec = (spec)
        match parse(.source = &empty_source, .specs = view(&schema), .allocator = allocator) {
            ..ok ~_ { abort }
            ..error error { if error.reason != ..invalid_cli_schema { abort } }
        }
    }
}

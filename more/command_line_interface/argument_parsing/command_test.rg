test cli_commands_and_diagnostics := (.system: System) -> !() {
    assume allocator := system.page_allocator
    specs ::= (
        Spec(.name = "output", .short_name = "o", .value_name = "FILE", .required = true),
    )
    commands ::= (
        Command(.name = "build", .about = "Compile a program", .specs = view(&specs)),
    )
    args: [3]StringView = ("build", "-o", "app")
    source ::= ArgumentViews(view(&args))
    parsed ::= parse_command(&source, .commands = view(&commands))!
    if parsed.command != "build" or parsed.help { abort }
    if contains(&parsed.matches, "output") == false { abort }
    if occurrences(&parsed.matches, "output") != 1 { abort }
    match value(&parsed.matches, "output") {
        ..none { abort }
        ..some entry { if entry.value != "app" { abort } }
    }

    help_args: [2]StringView = ("build", "--help")
    help_source ::= ArgumentViews(view(&help_args))
    help ::= parse_command(&help_source, .commands = view(&commands))!
    if help.help == false or help.command != "build" { abort }

    diagnostic ::= Diagnostic()
    bad_args: [2]StringView = ("build", "--unknown")
    bad_source ::= ArgumentViews(view(&bad_args))
    match parse_command(
        &bad_source, .commands = view(&commands), .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..unknown_option { abort } }
    }
    if diagnostic.argument != "unknown" or diagnostic.message != "unknown option" { abort }

    missing_args: [2]StringView = ("build", "--output")
    missing_source ::= ArgumentViews(view(&missing_args))
    match parse(
        .source     = &missing_source
        .start      = 1
        .specs      = view(&specs)
        .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..missing_option_value { abort } }
    }
    if diagnostic.argument != "output" { abort }
}

test cli_command_boundaries := (.system: System) -> !() {
    assume allocator := system.page_allocator
    specs ::= (Spec(.name = "output", .value_name = "FILE"),)
    commands ::= (Command(.name = "build", .specs = view(&specs)),)
    diagnostic ::= Diagnostic()
    empty: [0]StringView = ()
    empty_source ::= ArgumentViews(view(&empty))
    match parse_command(
        &empty_source, .commands = view(&commands), .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..missing_command { abort } }
    }
    unknown: [1]StringView = ("buid")
    unknown_source ::= ArgumentViews(view(&unknown))
    match parse_command(
        &unknown_source
        .commands   = view(&commands)
        .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..unknown_command { abort } }
    }
    if diagnostic.argument != "buid" { abort }
    literal: [3]StringView = ("build", "--", "--help")
    literal_source ::= ArgumentViews(view(&literal))
    parsed ::= parse_command(&literal_source, .commands = view(&commands))!
    if parsed.help or length(&parsed.matches.positionals) != 1 { abort }
    attached: [3]StringView = ("build", "--output", "--help")
    attached_source ::= ArgumentViews(view(&attached))
    valued ::= parse_command(&attached_source, .commands = view(&commands))!
    if valued.help { abort }
    match value(&valued.matches, "output") {
        ..none { abort }
        ..some entry { if entry.value != "--help" { abort } }
    }
    top: [1]StringView = ("--help")
    top_source ::= ArgumentViews(view(&top))
    help ::= parse_command(&top_source, .commands = view(&commands))!
    if help.help == false or help.command != "" { abort }
}

test cli_diagnostic_failures_and_reset := (.system: System) -> !() {
    assume allocator := system.page_allocator
    specs ::= (
        Spec(.name = "verbose", .short_name = "v"),
        Spec(.name = "output", .value_name = "FILE", .required = true)
    )
    diagnostic ::= Diagnostic()
    duplicate: [2]StringView = ("-v", "--verbose")
    duplicate_source ::= ArgumentViews(view(&duplicate))
    match parse(
        &duplicate_source, .specs = view(&specs), .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..duplicate_option { abort } }
    }
    if diagnostic.argument != "verbose" { abort }
    flag: [1]StringView = ("--verbose=yes")
    flag_source ::= ArgumentViews(view(&flag))
    match parse(
        &flag_source, .specs = view(&specs), .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..unexpected_option_value { abort } }
    }
    if diagnostic.value != "yes" { abort }
    empty: [0]StringView = ()
    empty_source ::= ArgumentViews(view(&empty))
    match parse(
        &empty_source, .specs = view(&specs), .diagnostic = ..some(.value = $&diagnostic)
    ) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..required_option { abort } }
    }
    if diagnostic.argument != "output" or diagnostic.value != "" { abort }
    good: [1]StringView = ("--output=app")
    good_source ::= ArgumentViews(view(&good))
    matches ::= parse(
        &good_source, .specs = view(&specs), .diagnostic = ..some(.value = $&diagnostic)
    )!
    if diagnostic.message != "" or diagnostic.argument != "" { abort }
    if occurrences(&matches, "absent") != 0 or contains(&matches, "absent") { abort }

    invalid ::= (Command(.name = "build", .specs = view(&specs)), Command(.name = "build"))
    match parse_command(&empty_source, .commands = view(&invalid)) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_cli_schema { abort } }
    }
    reserved_specs ::= (Spec(.name = "help"),)
    reserved ::= (Command(.name = "build", .specs = view(&reserved_specs)),)
    match parse_command(&empty_source, .commands = view(&reserved)) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_cli_schema { abort } }
    }
}

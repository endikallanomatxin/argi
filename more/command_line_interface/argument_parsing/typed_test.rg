_TestBuild := (
    .input  : Positional#(StringView),
    .output : Option#(
        StringView,
        .short_name    = "o",
        .help          = "Output file",
        .default_value = ..some(.value = "output")
    ),
    .verbose : Flag#(.short_name = "v")
)

test typed_record_arguments := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    args: [4]StringView = ("main.rg", "-o", "app", "-v")
    source ::= ArgumentViews(view(&args))
    parsed ::= parse#(_TestBuild)(.source = &source)!
    match parsed {
        ..help ~_ { abort }
        ..arguments data {
            if [
                data.input.value != "main.rg"
                or data.output.value != "app"
                or data.verbose.value == false
            ] { abort }
        }
    }
}

_TestRun := (.input: Positional#(StringView), .release: Flag#())

_TestCommand: Type = (..build _TestBuild, ..run _TestRun)

test typed_choice_arguments := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    args: [3]StringView = ("run", "main.rg", "--release")
    source ::= ArgumentViews(view(&args))
    parsed ::= parse#(_TestCommand)(.source = &source)!
    match parsed {
        ..help _ { abort }
        ..arguments command {
            match command {
                ..build _ { abort }
                ..run data {
                    if data.input.value != "main.rg" or data.release.value == false { abort }
                }
            }
        }
    }
}

_TestNumbers := (.jobs: Option#(UInt8), .input: Positional#(StringView))

_EmptyArgs: Type = ()

_TestEmptyCommand: Type = (..empty _EmptyArgs)

test typed_help_defaults_and_values := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    args: [1]StringView = ("main.rg")
    source ::= ArgumentViews(view(&args))
    match parse#(_TestBuild)(.source = &source)! {
        ..help _ { abort }
        ..arguments data {
            if data.output.value != "output" or data.verbose.value { abort }
        }
    }
    before: [3]StringView = ("--jobs", "8", "main.rg")
    before_source ::= ArgumentViews(view(&before))
    match parse#(_TestNumbers)(.source = &before_source)! {
        ..help _ { abort }
        ..arguments data { if data.jobs.value != 8 or data.input.value != "main.rg" { abort } }
    }
    invalid: [3]StringView = ("--jobs", "256", "main.rg")
    invalid_source ::= ArgumentViews(view(&invalid))
    match parse#(_TestNumbers)(.source = &invalid_source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_argument_value { abort } }
    }
    missing: [1]StringView = ("--verbose")
    missing_source ::= ArgumentViews(view(&missing))
    match parse#(_TestBuild)(.source = &missing_source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..required_option { abort } }
    }
    help_args: [2]StringView = ("build", "--help")
    help_source ::= ArgumentViews(view(&help_args))
    match parse#(_TestCommand)(.source = &help_source)! {
        ..arguments _ { abort }
        ..help info {
            if info.command != "build" { abort }
        }
    }
    empty_args: [1]StringView = ("empty")
    empty_source ::= ArgumentViews(view(&empty_args))
    match parse#(_TestEmptyCommand)(.source = &empty_source)! {
        ..help _ { abort }
        ..arguments command { match command { ..empty _ {} } }
    }
}

test typed_layout_and_help_output := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    if size_of(.type = Option#(UInt8)) != size_of(.type = UInt8) { abort }
    if size_of(.type = Flag#()) != size_of(.type = Bool) { abort }
    help_args: [1]StringView = ("--help")
    help_source ::= ArgumentViews(view(&help_args))
    parsed ::= parse#(_TestBuild)(.source = &help_source)!
    expected ::= "Compiler\nUsage: example <input> [OPTIONS]\n\nArguments and options:\n  input  \n  -o, --output <VALUE>  Output file\n  -v, --verbose  \n  -h, --help  Show help\n"
    output ::= _HelpOutput(.expected = expected)
    match parsed {
        ..arguments _ { abort }
        ..help info {
            write_typed_help#(_TestBuild)(
                $&output, &info, .program = "example", .about = "Compiler"
            )!! "writing CLI help"
        }
    }
    if output.index != byte_length(&expected) { abort }
    commands: [2]StringView = ("build", "--help")
    command_source ::= ArgumentViews(view(&commands))
    detail ::= "\nUsage: example build <input> [OPTIONS]\n\nArguments and options:\n  input  \n  -o, --output <VALUE>  Output file\n  -v, --verbose  \n  -h, --help  Show help\n"
    command_output ::= _HelpOutput(.expected = detail)
    match parse#(_TestCommand)(.source = &command_source)! {
        ..arguments _ { abort }
        ..help info {
            write_typed_help#(_TestCommand)(
                $&command_output, &info, .program = "example", .about = ""
            )!! "writing CLI help"
        }
    }
    if command_output.index != byte_length(&detail) { abort }
}

test typed_choice_errors_and_literal_help := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    unknown: [2]StringView = ("run", "--unknown")
    unknown_source ::= ArgumentViews(view(&unknown))
    match parse#(_TestCommand)(.source = &unknown_source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..unknown_option { abort } }
    }
    missing: [1]StringView = ("run")
    missing_source ::= ArgumentViews(view(&missing))
    match parse#(_TestCommand)(.source = &missing_source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..required_option { abort } }
    }
    literal: [3]StringView = ("run", "--", "--help")
    literal_source ::= ArgumentViews(view(&literal))
    match parse#(_TestCommand)(.source = &literal_source)! {
        ..help _ { abort }
        ..arguments command {
            match command {
                ..build _ { abort }
                ..run data { if data.input.value != "--help" { abort } }
            }
        }
    }
    value_args: [3]StringView = ("--output", "--help", "main.rg")
    value_source ::= ArgumentViews(view(&value_args))
    match parse#(_TestBuild)(.source = &value_source)! {
        ..help _ { abort }
        ..arguments data {
            if data.output.value != "--help" or data.input.value != "main.rg" { abort }
        }
    }
}

_InvalidHelpArgs := (.help: Flag#())

_InvalidHelpCommand: Type = (..run _InvalidHelpArgs)

test typed_command_help_validates_schema := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    args: [2]StringView = ("run", "--help")
    source ::= ArgumentViews(view(&args))
    match parse#(_InvalidHelpCommand)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_cli_schema { abort } }
    }
}

_FailingSource := (.reads: $&UIntNative)

implement ArgumentSource#(_FailingSource) (
    .length = (.self: &_FailingSource) -> (.count: UIntNative = 1) {}
    .get    = (.self: &_FailingSource, .index: UIntNative) -> (
        .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
    ) {
        self&.reads&= self&.reads&+ 1
        if self&.reads&>= 3 {
            result = ..error(.reason = ..invalid_utf8)
            return
        }
        result = ..ok "main.rg"
    }
)

test typed_source_errors_during_construction := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    reads :: UIntNative = 0
    source ::= _FailingSource(.reads = $&reads)
    match parse#(_TestRun)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_utf8 { abort } }
    }
    if reads != 3 { abort }
}

_TestInlineDefaults := (
    .count   : Option#(UInt8, .help = "Worker count", .default_value = ..some(.value = 7)),
    .enabled : Option#(Bool, .default_value = ..some(.value = true)),
    .input   : Positional#(StringView, .default_value = ..some(.value = "main.rg"))
)

test typed_inline_metadata_and_defaults := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    values: [0]StringView = ()
    source ::= ArgumentViews(view(&values))
    match parse#(_TestInlineDefaults)(.source = &source)! {
        ..help _ { abort }
        ..arguments data {
            if [
                data.count.value != 7
                or data.enabled.value == false
                or data.input.value != "main.rg"
            ] { abort }
        }
    }
    if [
        size_of(.type = Option#(UInt8, .help = "metadata", .default_value = ..some(.value = 7)))
        != size_of(.type = UInt8)
    ] { abort }
}

_LongNameArgs := (
    .output_file : Option#(StringView, .long_name = "output-file", .short_name = "o"),
    .no_cache    : Flag#(.long_name = "no-cache")
)

test typed_explicit_long_names := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    values: [3]StringView = ("--output-file", "app", "--no-cache")
    source ::= ArgumentViews(view(&values))
    match parse#(_LongNameArgs)(.source = &source)! {
        ..help _ { abort }
        ..arguments args {
            if args.output_file.value != "app" or args.no_cache.value == false { abort }
        }
    }
    aliases: [2]StringView = ("-o", "alias")
    alias_source ::= ArgumentViews(view(&aliases))
    match parse#(_LongNameArgs)(.source = &alias_source)! {
        ..help _ { abort }
        ..arguments args { if args.output_file.value != "alias" { abort } }
    }
}

test typed_optional_positional_help := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    expected ::= "\nUsage: example [input] [OPTIONS]\n\nArguments and options:\n  input  \n  -h, --help  Show help\n"
    output ::= _HelpOutput(.expected = expected)
    info ::= Help(.command = "")
    write_typed_help#(_DefaultInput)($&output, &info, .program = "example")!! "writing CLI help"
    if output.index != byte_length(&expected) { abort }
}

_DefaultInput := (.input: Positional#(StringView, .default_value = ..some(.value = ".")))

_DefaultCommand: Type = (
    ..run _TestRun,
    ..help Subcommand#(_EmptyArgs, .is_default = true, .long_alias = "help", .short_alias = "h"),
    ..version Subcommand#(_EmptyArgs, .long_alias = "version", .short_alias = "V")
)

test typed_default_command_and_aliases := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    empty: [0]StringView = ()
    source ::= ArgumentViews(view(&empty))
    match parse#(_DefaultCommand)(.source = &source)! {
        ..help _ { abort }
        ..arguments command {
            match command { ..help _ {} ..run _ { abort } ..version _ { abort } }
        }
    }
    version_tokens: [3]StringView = ("--version", "-V", "version")
    for token in version_tokens {
        values: [1]StringView = (token)
        selected ::= ArgumentViews(view(&values))
        match parse#(_DefaultCommand)(.source = &selected)! {
            ..help _ { abort }
            ..arguments command {
                match command { ..version _ {} ..run _ { abort } ..help _ { abort } }
            }
        }
    }
    help_tokens: [3]StringView = ("--help", "-h", "help")
    for token in help_tokens {
        values: [1]StringView = (token)
        selected ::= ArgumentViews(view(&values))
        match parse#(_DefaultCommand)(.source = &selected)! {
            ..help _ { abort }
            ..arguments command {
                match command { ..help _ {} ..run _ { abort } ..version _ { abort } }
            }
        }
    }
    detail: [2]StringView = ("run", "--help")
    detail_source ::= ArgumentViews(view(&detail))
    match parse#(_DefaultCommand)(.source = &detail_source)! {
        ..arguments ~_ { abort }
        ..help info { if info.command != "run" { abort } }
    }
    literal: [3]StringView = ("run", "--", "--version")
    literal_source ::= ArgumentViews(view(&literal))
    match parse#(_DefaultCommand)(.source = &literal_source)! {
        ..help _ { abort }
        ..arguments command {
            match command {
                ..run args { if args.input.value != "--version" { abort } }
                ..help _ { abort }
                ..version _ { abort }
            }
        }
    }
}

_TwoDefaults: Type = (
    ..first Subcommand#(_EmptyArgs, .is_default = true),
    ..second Subcommand#(_EmptyArgs, .is_default = true)
)

_DuplicateAliases: Type = (
    ..first Subcommand#(_EmptyArgs, .long_alias = "same"),
    ..second Subcommand#(_EmptyArgs, .long_alias = "same")
)

_RequiredDefault: Type = (..run Subcommand#(_TestRun, .is_default = true))

_WrappedBuild: Type = (..build Subcommand#(_TestBuild, .long_alias = "build"))

test typed_command_metadata_validation := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    empty: [0]StringView = ()
    source ::= ArgumentViews(view(&empty))
    match parse#(_TwoDefaults)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_cli_schema { abort } }
    }
    match parse#(_DuplicateAliases)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_cli_schema { abort } }
    }
    match parse#(_RequiredDefault)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..required_option { abort } }
    }
    values: [4]StringView = ("--build", "--output", "--version", "main.rg")
    selected ::= ArgumentViews(view(&values))
    match parse#(_WrappedBuild)(.source = &selected)! {
        ..help _ { abort }
        ..arguments command {
            match command {
                ..build data {
                    if [
                        data.arguments.output.value != "--version"
                        or data.arguments.input.value != "main.rg"
                    ] { abort }
                }
            }
        }
    }
    detail: [2]StringView = ("build", "--help")
    detail_source ::= ArgumentViews(view(&detail))
    match parse#(_WrappedBuild)(.source = &detail_source)! {
        ..arguments ~_ { abort }
        ..help info { if info.command != "build" { abort } }
    }
}

_ParseTrace := (
    .message_seen  : Bool       = false,
    .argument_seen : Bool       = false,
    .value_seen    : Bool       = false,
    .count         : UIntNative = 0
)

implement ErrorTracer#(_ParseTrace) (
    .add_context = (.self: $&_ParseTrace, .location: SourceLocationId, .context: StringView) -> (
    ) {
        self&.count = self&.count + 1
        if context == "invalid argument value" { self&.message_seen = true }
        if context == "jobs" { self&.argument_seen = true }
        if context == "256" { self&.value_seen = true }
    }
    .reset_context = (.self: $&_ParseTrace) -> () {
        self&.message_seen = false
        self&.argument_seen = false
        self&.value_seen = false
        self&.count = 0
    }
    .report = (.self: $&_ParseTrace, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) {}
)

test typed_parse_records_error_context_only_on_failure := (.system: System) -> !!() {
    assume allocator := system.page_allocator
    tracer ::= _ParseTrace()
    assume error_tracer ::= $&Virtual#(ErrorTracer)($&tracer)
    values: [3]StringView = ("--jobs", "256", "main.rg")
    source ::= ArgumentViews(view(&values))
    match parse#(_TestNumbers)(.source = &source) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..invalid_argument_value { abort } }
    }
    if [
        tracer.message_seen == false
        or tracer.argument_seen == false
        or tracer.value_seen == false
    ] { abort }
    ErrorTracer#().reset_context(.self = error_tracer)
    help_args: [1]StringView = ("--help")
    help_source ::= ArgumentViews(view(&help_args))
    help_result ::= parse#(_TestNumbers)(.source = &help_source) handle ignored, recovered {
        abort
    }
    match help_result {
        ..arguments _ { abort }
        ..help _ {}
    }
    if tracer.count != 0 { abort }
    valid: [3]StringView = ("--jobs", "8", "main.rg")
    valid_source ::= ArgumentViews(view(&valid))
    valid_result ::= parse#(_TestNumbers)(.source = &valid_source) handle ignored, recovered {
        abort
    }
    match valid_result {
        ..arguments args { if args.jobs.value != 8 { abort } }
        ..help _ { abort }
    }
    if tracer.count != 0 { abort }
}

_local_parse_failure := (
    .allocator: Virtual#(Allocator), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, TypedReasons, ErrorWithTrace#(TypedReasons))) {
    values: [3]StringView = ("--jobs", "256", "main.rg")
    source ::= ArgumentViews(view(&values))
    match parse#(_TestNumbers)(
        .source = &source, .allocator = allocator, .error_tracer = error_tracer
    ) {
        ..ok ~_ { abort }
        ..error error { result = ..error error }
    }
}

test typed_parse_error_outlives_local_argument_source := (.system: System) -> !() {
    tracer ::= _ParseTrace()
    handle ::= Virtual#(ErrorTracer)($&tracer)
    match _local_parse_failure(.allocator = system.page_allocator, .error_tracer = $&handle) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_argument_value { abort } }
    }
    if tracer.argument_seen == false or tracer.value_seen == false { abort }
}

..invalid_argument_value
..unexpected_positional

Help := (.command: StringView)

TypedReasons: Type = (
    ..invalid_argument_value,
    ..unexpected_positional,
    ..unknown_command,
    ..missing_command,
    ..invalid_utf8,
    ..out_of_bounds,
    ..invalid_option,
    ..missing_option_value,
    ..unknown_option,
    ..duplicate_option,
    ..required_option,
    ..unexpected_option_value,
    ..invalid_cli_schema,
    ..out_of_memory
)

_field_info := #(.Field: Type: ArgumentField#(Field)) (.name: StringView, .context: Int32) -> (
    .info : FieldInfo
) {
    info = ArgumentField#(Field).describe(name)
}

_ReadContext := #(.Source: Type) (
    .source     : &Source,
    .start      : UIntNative,
    .specs      : ArrayView#(Spec),
    .position   : UIntNative        = 0,
    .failed     : Bool              = false,
    .reason     : TypedReasons      = ..invalid_argument_value,
    .diagnostic : ?$&Diagnostic
)

_read_field := #(.Field: Type: ArgumentField#(Field), .Source: Type: ArgumentSource#(Source)) (
    .name: StringView, .context: $&_ReadContext#(Source)
) -> (.field: Field) {
    if context&.failed {
        field = ArgumentField#(Field).empty()
        return
    }
    info ::= ArgumentField#(Field).describe(name)
    text :: ?StringView = ..none
    present ::= false
    parser ::= Parser#(Source)(.source = context&.source, .start = context&.start)
    position :: UIntNative = 0
    while true {
        token ::= next($&parser) handle error, recovered {
            context&.failed = true
            match error.reason {
                ..invalid_option { context&.reason = ..invalid_option }
                ..invalid_utf8 { context&.reason = ..invalid_utf8 }
                ..out_of_bounds { context&.reason = ..out_of_bounds }
            }
            field = ArgumentField#(Field).empty()
            return
        }
        match token {
            ..none { break }
            ..some item {
                match item.value {
                    ..positional value {
                        if info.positional and position == context&.position {
                            text = ..some(.value = value)
                            present = true
                        }
                        position = position + 1
                    }
                    ..option option {
                        for spec in context&.specs {
                            if [
                                [option.short and option.name == spec.short_name]
                                or [option.short == false and option.name == spec.name]
                            ] {
                                consumed :: ?StringView = ..none
                                if byte_length(&spec.value_name) > 0 {
                                    parsed ::= take_value($&parser, option) handle error, recovered {
                                        context&.failed = true
                                        match error.reason {
                                            ..missing_option_value {
                                                context&.reason = ..missing_option_value
                                            }
                                            ..invalid_utf8 { context&.reason = ..invalid_utf8 }
                                            ..out_of_bounds {
                                                context&.reason = ..out_of_bounds
                                            }
                                        }
                                        field = ArgumentField#(Field).empty()
                                        return
                                    }
                                    consumed = ..some(.value = parsed)
                                }
                                if info.positional == false and spec.name == info.spec.name {
                                    present = true
                                    text = consumed
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if info.positional { context&.position = context&.position + 1 }
    match ArgumentField#(Field).read(text, present) {
        ..ok ~parsed { field = ~parsed }
        ..error error {
            context&.failed = true
            match error.reason {
                ..required_option { context&.reason = ..required_option }
                ..invalid_argument_value { context&.reason = ..invalid_argument_value }
            }
            shown :: StringView = ""
            match text { ..none {} ..some entry { shown = entry.value } }
            _set_diagnostic(
                context&.diagnostic
                .argument = info.spec.name
                .value    = shown
                .message  = "missing or invalid argument value"
            )
            field = ArgumentField#(Field).empty()
        }
    }
}

_wants_typed_help := #(.Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .start      : UIntNative,
    .specs      : ArrayView#(Spec),
    .diagnostic : ?$&Diagnostic     = ..none
) -> (.result: Errable#(Bool, TypedReasons)) {
    parser ::= Parser(.source = source, .start = start)
    while true {
        match next($&parser)! {
            ..none { break }
            ..some item {
                match item.value {
                    ..positional _ {}
                    ..option option {
                        if [
                            [option.name == "help" and option.short == false]
                            or [option.name == "h" and option.short]
                        ] {
                            match option.value {
                                ..none {
                                    result = ..ok true
                                    return
                                }
                                ..some _ {
                                    result = ..error(.reason = ..unexpected_option_value)
                                    return
                                }
                            }
                        } else {
                            for spec in specs {
                                if [
                                    [option.short and option.name == spec.short_name]
                                    or [option.short == false and option.name == spec.name]
                                ] {
                                    if byte_length(&spec.value_name) > 0 {
                                        taken ::= take_value($&parser, option) handle error, recovered {
                                            _set_diagnostic(
                                                diagnostic
                                                .argument = spec.name
                                                .message  = "option requires a value"
                                            )
                                            match error.reason {
                                                ..missing_option_value {
                                                    result = ..error(
                                                        .reason = ..missing_option_value
                                                    )
                                                }
                                                ..invalid_utf8 {
                                                    result = ..error(.reason = ..invalid_utf8)
                                                }
                                                ..out_of_bounds {
                                                    result = ..error(.reason = ..out_of_bounds)
                                                }
                                            }
                                            return
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    result = ..ok false
}

_parse_record := #(.T: Type, .Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .start      : UIntNative,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic
) -> (.result: Errable#(T, TypedReasons)) {
    assume allocator
    fixed_specs ::= collect_fields#(T, _field_info, FieldInfo)(.context = Int32())
    specs ::= DynamicArray#(Spec)(.capacity = 4)!
    for info in fixed_specs {
        if info.positional == false {
            push(.self = $&specs, .value = info.spec, .allocator = allocator)!
        }
    }
    _validate_specs(view(&specs))!
    matches ::= parse_specs(
        .source = source, .specs = view(&specs), .start = start, .diagnostic = diagnostic
    )!
    reader ::= _ReadContext#(Source)(
        .source = source, .start = start, .specs = view(&specs), .diagnostic = diagnostic
    )
    arguments ::= construct_record#(T, _read_field)(.context = $&reader)
    if reader.failed {
        result = ..error(.reason = reader.reason)
        return
    }
    if reader.position < length(&matches.positionals) {
        result = ..error(.reason = ..unexpected_positional)
        return
    }
    result = ..ok ~arguments
}

_parse_typed := #(.T: Type, .Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .start      : UIntNative           = 0,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic        = ..none
) -> (.result: Errable#(T, TypedReasons)) {
    #if is_choice_type(.type = T) {
        result = _parse_choice#(T)(
            .source = source, .start = start, .allocator = allocator, .diagnostic = diagnostic
        )
    } #else {
        result = _parse_record#(T)(
            .source = source, .start = start, .allocator = allocator, .diagnostic = diagnostic
        )
    }
}

parse := #(.T: Type, .Source: Type: ArgumentSource#(Source)) (
    .source       : &Source,
    .start        : UIntNative              = 0,
    .allocator    : Virtual#(Allocator),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(T, TypedReasons, ErrorWithTrace#(TypedReasons))) {
    diagnostic ::= Diagnostic()
    diagnostic_ref: ?$&Diagnostic = ..some(.value = $&diagnostic)
    match _parse_typed#(T, Source)(
        source, .start = start, .allocator = allocator, .diagnostic = diagnostic_ref
    ) {
        ..ok ~parsed { result = ..ok ~parsed }
        ..error error {
            tracer ::= capture_error_tracer(
                .location = error_location_id(), .error_tracer = error_tracer
            )
            add_context(.context = "invalid command-line arguments", .error_tracer = tracer)
            add_context(.context = _typed_reason_text(error.reason), .error_tracer = tracer)
            if byte_length(&diagnostic.message) > 0 {
                add_context(.context = diagnostic.message, .error_tracer = tracer)
            }
            if byte_length(&diagnostic.argument) > 0 {
                add_context(.context = "argument:", .error_tracer = tracer)
                add_context(.context = diagnostic.argument, .error_tracer = tracer)
            }
            if byte_length(&diagnostic.value) > 0 {
                add_context(.context = "value:", .error_tracer = tracer)
                add_context(.context = diagnostic.value, .error_tracer = tracer)
            }
            result = ..error(.reason = error.reason, .tracer = tracer)
        }
    }
}

_typed_reason_text := (.reason: TypedReasons) -> (.text: StringView) {
    match reason {
        ..invalid_argument_value { text = "invalid argument value" }
        ..unexpected_positional { text = "unexpected positional argument" }
        ..unknown_command { text = "unknown command" }
        ..missing_command { text = "missing command" }
        ..invalid_utf8 { text = "invalid UTF-8 in arguments" }
        ..out_of_bounds { text = "argument source index out of bounds" }
        ..invalid_option { text = "invalid option syntax" }
        ..missing_option_value { text = "missing option value" }
        ..unknown_option { text = "unknown option" }
        ..duplicate_option { text = "duplicate option" }
        ..required_option { text = "missing required argument" }
        ..unexpected_option_value { text = "unexpected option value" }
        ..invalid_cli_schema { text = "invalid command-line schema" }
        ..out_of_memory { text = "out of memory while parsing arguments" }
    }
}

_help_record := #(.T: Type, .W: Type: Writer#(W)) (
    .writer         : $&W,
    .program        : StringView,
    .about          : StringView,
    .parent         : StringView  = "",
    .automatic_help : Bool        = false
) -> !() {
    infos ::= collect_fields#(T, _field_info, FieldInfo)(.context = Int32())
    write(writer, about)!
    write(writer, "\nUsage: ")!
    if byte_length(&parent) > 0 {
        write(writer, parent)!
        write(writer, " ")!
    }
    write(writer, program)!
    for info in infos {
        if info.positional {
            if info.spec.required { write(writer, " <")! } else { write(writer, " [")! }
            write(writer, info.spec.name)!
            if info.spec.required { write(writer, ">")! } else { write(writer, "]")! }
        }
    }
    write(writer, " [OPTIONS]\n\nArguments and options:\n")!
    for info in infos {
        if info.positional {
            write(writer, "  ")!
            write(writer, info.spec.name)!
            write(writer, "  ")!
            write(writer, info.spec.help)!
            write(writer, "\n")!
        } else {
            _write_option(writer, info.spec)!
        }
    }
    if automatic_help { write(writer, "  -h, --help  Show help\n")! }
}

_ChoiceContext := #(.Source: Type) (
    .source      : &Source,
    .start       : UIntNative,
    .name        : StringView,
    .allocator   : Virtual#(Allocator),
    .diagnostic  : ?$&Diagnostic,
    .failed      : Bool                 = false,
    .help        : Bool                 = false,
    .help_target : StringView           = "",
    .reason      : TypedReasons         = ..invalid_argument_value
)

_command_info := #(.Payload: Type) (.name: StringView, .context: Int32) -> (
    .command : SubcommandInfo
) {
    command = SubcommandPayload#(Payload).describe(name)
}

_choose_payload := #(.Payload: Type, .Source: Type) (
    .name: StringView, .context: $&_ChoiceContext#(Source)
) -> (.selected: Bool) {
    selected = name == context&.name
}

_empty_field := #(.Field: Type: ArgumentField#(Field), .Context: Type) (
    .name: StringView, .context: Context
) -> (.field: Field) {
    field = ArgumentField#(Field).empty()
}

_read_payload := #(.Payload: Type, .Source: Type: ArgumentSource#(Source)) (
    .name: StringView, .context: $&_ChoiceContext#(Source)
) -> (.payload: Payload) {
    match _parse_record#(SubcommandPayload#(Payload).Arguments)(
        .source     = context&.source
        .start      = context&.start
        .allocator  = context&.allocator
        .diagnostic = context&.diagnostic
    ) {
        ..ok ~arguments {
            payload = SubcommandPayload#(Payload).wrap(~arguments)
            return
        }
        ..error error {
            context&.failed = true
            context&.reason = error.reason
        }
    }
    empty ::= construct_record#(SubcommandPayload#(Payload).Arguments, _empty_field)(
        .context = Int32()
    )
    payload = SubcommandPayload#(Payload).wrap(~empty)
}

_probe_payload_help := #(.Payload: Type, .Source: Type: ArgumentSource#(Source)) (
    .name: StringView, .context: $&_ChoiceContext#(Source)
) -> () {
    if name == context&.name {
        infos ::= collect_fields#(SubcommandPayload#(Payload).Arguments, _field_info, FieldInfo)(
            .context = Int32()
        )
        -- Value-taking options must consume their operands during help scanning.
        specs ::= DynamicArray#(Spec)(.capacity = 4, .allocator = context&.allocator) handle ignored, recovered {
            context&.failed = true
            context&.reason = ..out_of_memory
            return
        }
        for info in infos {
            if info.positional == false {
                if info.spec.name == "help" or info.spec.short_name == "h" {
                    context&.failed = true
                    context&.reason = ..invalid_cli_schema
                    return
                }
                push(.self = $&specs, .value = info.spec, .allocator = context&.allocator) handle ignored {
                    context&.failed = true
                    context&.reason = ..out_of_memory
                    return
                }
            }
        }
        _validate_specs(view(&specs)) handle ignored, recovered {
            context&.failed = true
            context&.reason = ..invalid_cli_schema
            return
        }
        match _wants_typed_help(
            .source     = context&.source
            .start      = context&.start
            .specs      = view(&specs)
            .diagnostic = context&.diagnostic
        ) {
            ..ok requested { context&.help = requested }
            ..error error {
                context&.failed = true
                context&.reason = error.reason
            }
        }
    }
}

_parse_choice := #(.T: Type, .Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .start      : UIntNative,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic
) -> (.result: Errable#(T, TypedReasons)) {
    _set_diagnostic(diagnostic, .argument = "", .message = "")
    commands ::= collect_variants#(T, _command_info, SubcommandInfo)(.context = Int32())
    defaults :: UIntNative = 0
    help_count :: UIntNative = 0
    help_name :: StringView = ""
    for command in commands {
        if command.is_default { defaults = defaults + 1 }
        if command.is_help {
            help_count = help_count + 1;
            help_name = command.name
        }
        if [
            byte_length(&command.short_alias) > 1
            or _valid_cli_option_name(command.long_alias) == false
            or _valid_cli_option_name(command.short_alias) == false
        ] {
            result = ..error(.reason = ..invalid_cli_schema);
            return
        }
        for other in commands {
            if command.name != other.name {
                if [
                    [command.long_alias != "" and command.long_alias == other.long_alias]
                    or [command.short_alias != "" and command.short_alias == other.short_alias]
                ] {
                    result = ..error(.reason = ..invalid_cli_schema);
                    return
                }
            }
        }
    }
    if defaults > 1 or help_count > 1 {
        result = ..error(.reason = ..invalid_cli_schema);
        return
    }
    name :: StringView = ""
    next_start ::= start
    if start >= ArgumentSource#().length(source) {
        for command in commands { if command.is_default { name = command.name } }
        if name == "" {
            result = ..error(.reason = ..missing_command);
            return
        }
    } else {
        token ::= ArgumentSource#().get(source, start)!
        next_start = start + 1
        for command in commands {
            if token == command.name { name = command.name }
            if [
                command.long_alias != ""
                and _command_alias(token, command.long_alias, .short = false)
            ] { name = command.name }
            if [
                command.short_alias != ""
                and _command_alias(token, command.short_alias, .short = true)
            ] { name = command.name }
        }
        if name == "" {
            _set_diagnostic(diagnostic, .argument = token, .message = "unknown command")
            result = ..error(.reason = ..unknown_command);
            return
        }
    }
    context ::= _ChoiceContext#(Source)(
        .source     = source
        .start      = next_start
        .name       = name
        .allocator  = allocator
        .diagnostic = diagnostic
    )
    if help_count > 0 {
        visit_variants#(T, _probe_payload_help)(.context = $&context)
        if context.failed {
            result = ..error(.reason = context.reason)
            return
        }
        if context.help {
            context.help_target = name
            context.name = help_name
            result = ..ok construct_choice#(T, _make_help_payload, _choose_payload)(
                .context = $&context
            )
            return
        }
    }
    if name == help_name {
        requested ::= _parse_record#(_HelpArguments)(
            .source     = source
            .start      = next_start
            .allocator  = allocator
            .diagnostic = diagnostic
        )!
        target ::= requested.command.value
        if target != "" {
            known ::= false
            for command in commands { if command.name == target { known = true } }
            if known == false {
                _set_diagnostic(
                    diagnostic, .argument = target, .message = "unknown help command"
                )
                result = ..error(.reason = ..unknown_command)
                return
            }
        }
        context.name = help_name
        context.help_target = target
        result = ..ok construct_choice#(T, _make_help_payload, _choose_payload)(
            .context = $&context
        )
        return
    }
    command ::= construct_choice#(T, _read_payload, _choose_payload)(.context = $&context)
    if context.failed {
        result = ..error(.reason = context.reason)
        return
    }
    result = ..ok ~command
}

_make_help_payload := #(.Payload: Type, .Source: Type) (
    .name: StringView, .context: $&_ChoiceContext#(Source)
) -> (.payload: Payload) {
    payload = SubcommandPayload#(Payload).from_help(context&.help_target)
}

_HelpContext := #(.W: Type) (
    .writer         : $&W,
    .command        : StringView,
    .program        : StringView,
    .failed         : Bool        = false,
    .automatic_help : Bool        = false
)

_write_payload_help := #(.Payload: Type, .W: Type: Writer#(W)) (
    .name: StringView, .context: $&_HelpContext#(W)
) -> () {
    if name == context&.command {
        _help_record#(SubcommandPayload#(Payload).Arguments)(
            context&.writer
            .program        = name
            .about          = ""
            .parent         = context&.program
            .automatic_help = context&.automatic_help
        ) handle error { context&.failed = true }
    }
}

_write_command_name := #(.Payload: Type, .W: Type: Writer#(W)) (
    .name: StringView, .context: $&_HelpContext#(W)
) -> () {
    write(context&.writer, "  ") handle error { context&.failed = true }
    write(context&.writer, name) handle error { context&.failed = true }
    info ::= SubcommandPayload#(Payload).describe(name)
    if info.long_alias != "" {
        write(context&.writer, " (--") handle error { context&.failed = true }
        write(context&.writer, info.long_alias) handle error { context&.failed = true }
        write(context&.writer, ")") handle error { context&.failed = true }
    }
    if info.short_alias != "" {
        write(context&.writer, " (-") handle error { context&.failed = true }
        write(context&.writer, info.short_alias) handle error { context&.failed = true }
        write(context&.writer, ")") handle error { context&.failed = true }
    }
    if info.is_default {
        write(context&.writer, " [default]") handle error { context&.failed = true }
    }
    write(context&.writer, "\n") handle error { context&.failed = true }
}

write_typed_help := #(.T: Type, .W: Type: Writer#(W)) (
    .writer: $&W, .help: &Help, .program: StringView, .about: StringView = ""
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()) {
    #if is_choice_type(.type = T) {
        infos ::= collect_variants#(T, _command_info, SubcommandInfo)(.context = Int32())
        automatic_help ::= false
        for info in infos { if info.is_help { automatic_help = true } }

        if byte_length(&help&.command) == 0 {
            write(writer, about)!
            write(writer, "\nUsage: ")!
            write(writer, program)!
            write(writer, " <COMMAND> [OPTIONS] [ARGS]\n\nCommands:\n")!
            context ::= _HelpContext#(W)(.writer = writer, .command = "", .program = program)
            visit_variants#(T, _write_command_name)(.context = $&context)
            if context.failed {
                result = ..error(.reason = ..stream_write_failed)
                return
            }
            if automatic_help {
                write(writer, "\nUse <COMMAND> --help for command help.\n")!
            }
        } else {
            context ::= _HelpContext#(W)(
                .writer         = writer
                .command        = help&.command
                .program        = program
                .automatic_help = automatic_help
            )
            visit_variants#(T, _write_payload_help)(.context = $&context)
            if context.failed {
                result = ..error(.reason = ..stream_write_failed)
                return
            }
        }
    } #else {
        _help_record#(T)(writer, .program = program, .about = about)!
    }
}

_command_alias := (.token: StringView, .alias: StringView, .short: Bool) -> (
    .matches : Bool = false
) {
    prefix :: UIntNative = 2
    if short { prefix = 1 }
    if byte_length(&token) != byte_length(&alias) + prefix { return }
    index :: UIntNative = 0
    while index < prefix {
        byte ::= bytes_get(&token, index) handle ignored, recovered { return }
        if byte != 45 { return }
        index = index + 1
    }
    index = 0
    while index < byte_length(&alias).count {
        left ::= bytes_get(&token, index + prefix) handle ignored, recovered { return }
        right ::= bytes_get(&alias, index) handle ignored, recovered { return }
        if left != right { return }
        index = index + 1
    }
    matches = true
}

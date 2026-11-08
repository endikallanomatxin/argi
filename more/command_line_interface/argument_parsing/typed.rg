..invalid_argument_value
..unexpected_positional

Help := (.command: StringView)

Parsed := #(.T: Type) (..help Help, ..arguments T)

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
    .source: &Source, .start: UIntNative, .specs: ArrayView#(Spec)
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
                                        _ ::= take_value($&parser, option)!
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
) -> (.result: Errable#(Parsed#(T), TypedReasons)) {
    assume allocator
    fixed_specs ::= collect_fields#(T, _field_info, FieldInfo)(.context = Int32())
    specs ::= DynamicArray#(Spec)(.capacity = 4)!
    for info in fixed_specs {
        if info.positional == false {
            if info.spec.name == "help" or info.spec.short_name == "h" {
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
            push(.self = $&specs, .value = info.spec, .allocator = allocator)!
        }
    }
    _validate_specs(view(&specs))!
    wants_help ::= _wants_typed_help(.source = source, .start = start, .specs = view(&specs))!
    if wants_help {
        result = ..ok ..help(.command = "")
        return
    }
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
    result = ..ok ..arguments ~arguments
}

parse := #(.T: Type, .Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .start      : UIntNative           = 0,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic        = ..none
) -> (.result: Errable#(Parsed#(T), TypedReasons)) {
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

_help_record := #(.T: Type, .W: Type: Writer#(W)) (
    .writer: $&W, .program: StringView, .about: StringView, .parent: StringView = ""
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
    write(writer, "  -h, --help  Show help\n")!
}

_ChoiceContext := #(.Source: Type) (
    .source     : &Source,
    .start      : UIntNative,
    .name       : StringView,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic,
    .failed     : Bool                 = false,
    .help       : Bool                 = false,
    .reason     : TypedReasons         = ..invalid_argument_value
)

_command_info := #(.Payload: Type) (.name: StringView, .context: Int32) -> (.command: Command) {
    command = Command(.name = name)
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
    match _parse_record#(Payload)(
        .source     = context&.source
        .start      = context&.start
        .allocator  = context&.allocator
        .diagnostic = context&.diagnostic
    ) {
        ..ok ~parsed {
            match parsed {
                ..arguments ~arguments {
                    payload = ~arguments
                    return
                }
                ..help _ { context&.help = true }
            }
        }
        ..error error {
            context&.failed = true
            context&.reason = error.reason
        }
    }
    payload = construct_record#(Payload, _empty_field)(.context = Int32())
}

_probe_payload_help := #(.Payload: Type, .Source: Type: ArgumentSource#(Source)) (
    .name: StringView, .context: $&_ChoiceContext#(Source)
) -> () {
    if name == context&.name {
        infos ::= collect_fields#(Payload, _field_info, FieldInfo)(.context = Int32())
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
            .source = context&.source, .start = context&.start, .specs = view(&specs)
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
) -> (.result: Errable#(Parsed#(T), TypedReasons)) {
    _set_diagnostic(diagnostic, .argument = "", .message = "")
    commands ::= collect_variants#(T, _command_info, Command)(.context = Int32())
    if start >= ArgumentSource#().length(source) {
        result = ..error(.reason = ..missing_command)
        return
    }
    name ::= ArgumentSource#().get(source, start)!
    if name == "--help" or name == "-h" {
        result = ..ok ..help(.command = "")
        return
    }
    found ::= false
    for command in commands { if command.name == name { found = true } }
    if found == false {
        _set_diagnostic(diagnostic, .argument = name, .message = "unknown command")
        result = ..error(.reason = ..unknown_command)
        return
    }
    context ::= _ChoiceContext#(Source)(
        .source     = source
        .start      = start + 1
        .name       = name
        .allocator  = allocator
        .diagnostic = diagnostic
    )
    visit_variants#(T, _probe_payload_help)(.context = $&context)
    if context.failed {
        result = ..error(.reason = context.reason)
        return
    }
    if context.help {
        result = ..ok ..help(.command = name)
        return
    }
    command ::= construct_choice#(T, _read_payload, _choose_payload)(.context = $&context)
    if context.failed {
        result = ..error(.reason = context.reason)
        return
    }
    if context.help {
        result = ..ok ..help(.command = name)
        return
    }
    result = ..ok ..arguments ~command
}

_HelpContext := #(.W: Type) (
    .writer  : $&W,
    .command : StringView,
    .program : StringView,
    .failed  : Bool        = false
)

_write_payload_help := #(.Payload: Type, .W: Type: Writer#(W)) (
    .name: StringView, .context: $&_HelpContext#(W)
) -> () {
    if name == context&.command {
        _help_record#(Payload)(
            context&.writer, .program = name, .about = "", .parent = context&.program
        ) handle error { context&.failed = true }
    }
}

_write_command_name := #(.Payload: Type, .W: Type: Writer#(W)) (
    .name: StringView, .context: $&_HelpContext#(W)
) -> () {
    write(context&.writer, "  ") handle error { context&.failed = true }
    write(context&.writer, name) handle error { context&.failed = true }
    write(context&.writer, "\n") handle error { context&.failed = true }
}

write_typed_help := #(.T: Type, .W: Type: Writer#(W)) (
    .writer: $&W, .help: &Help, .program: StringView, .about: StringView = ""
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()) {
    #if is_choice_type(.type = T) {
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
            write(writer, "\nUse <COMMAND> --help for command help.\n  -h, --help  Show help\n")!
        } else {
            context ::= _HelpContext#(W)(
                .writer = writer, .command = help&.command, .program = program
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

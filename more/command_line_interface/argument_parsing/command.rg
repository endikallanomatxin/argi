..unknown_command
..missing_command

-- One command level keeps dispatch explicit. Reuse the same specs in multiple
-- commands when they share options; no ambient/global option inheritance occurs.
Command := (
    .name  : StringView,
    .about : StringView       = "",
    .specs : ArrayView#(Spec) = empty_array_view#(Spec)()
)

implement ImplicitlyCopyable#(Command) ()

Invocation := (
    .command : StringView,
    .help    : Bool,
    .matches : Matches
)

CommandReasons: Type = (
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

parse_command := #(.Source: Type: ArgumentSource#(Source)) (
    .source     : &Source,
    .commands   : ArrayView#(Command),
    .start      : UIntNative           = 0,
    .allocator  : Virtual#(Allocator),
    .diagnostic : ?$&Diagnostic        = ..none
) -> (.result: Errable#(Invocation, CommandReasons)) {
    assume allocator
    _set_diagnostic(diagnostic, .argument = "", .message = "")
    for command in commands {
        _validate_specs(command.specs)!
        for spec in command.specs {
            if spec.name == "help" or spec.short_name == "h" {
                _set_diagnostic(
                    diagnostic
                    .argument = spec.name
                    .message  = "command options reserve --help and -h"
                )
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
        }
        if [
            byte_length(&command.name) == 0
            or _valid_cli_option_name(command.name) == false
            or command.name == "-h"
            or command.name == "--help"
        ] {
            result = ..error(.reason = ..invalid_cli_schema)
            return
        }

    }
    index :: UIntNative = 0
    while index < length(&commands) {
        command ::= get(&commands, index)!
        previous :: UIntNative = 0
        while previous < index {
            other ::= get(&commands, previous)!
            if command.name == other.name {
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
            previous = previous + 1
        }
        index = index + 1
    }
    if start >= ArgumentSource#().length(source) {
        _set_diagnostic(diagnostic, .argument = "", .message = "a command is required")
        result = ..error(.reason = ..missing_command)
        return
    }
    name ::= ArgumentSource#().get(source, start)!
    if name == "--help" or name == "-h" {
        options ::= DynamicArray#(Value)(.capacity = 0)!
        positionals ::= DynamicArray#(StringView)(.capacity = 0)!
        matches :: Matches = (.options = ~options, .positionals = ~positionals)
        result = ..ok(.command = "", .help = true, .matches = ~matches)
        return
    }
    for command in commands {
        if command.name == name {
            -- Help is an explicit successful outcome. Scan with the ordinary
            -- parser so values named --help and tokens after -- stay values.
            parser ::= Parser#(.t: Source)(.source = source, .start = start + 1)
            wants_help ::= false
            while true {
                match next($&parser)! {
                    ..none { break }
                    ..some entry {
                        match entry.value {
                            ..positional _ {}
                            ..option option {
                                if [
                                    [option.name == "help" and option.short == false]
                                    or [option.name == "h" and option.short]
                                ] {
                                    match option.value {
                                        ..none { wants_help = true }
                                        ..some _ {}
                                    }
                                } else {
                                    for spec in command.specs {
                                        if [
                                            [
                                                option.short
                                                and option.name == spec.short_name
                                            ]
                                            or [
                                                option.short == false
                                                and option.name == spec.name
                                            ]
                                        ] {
                                            if byte_length(&spec.value_name) > 0 {
                                                _set_diagnostic(
                                                    diagnostic
                                                    .argument = spec.name
                                                    .message  = "option requires a value"
                                                )
                                                _ ::= take_value($&parser, option)!
                                                _set_diagnostic(
                                                    diagnostic, .argument = "", .message = ""
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if wants_help {
                options ::= DynamicArray#(Value)(.capacity = 0)!
                positionals ::= DynamicArray#(StringView)(.capacity = 0)!
                matches :: Matches = (.options = ~options, .positionals = ~positionals)
                result = ..ok(.command = name, .help = true, .matches = ~matches)
                return
            }
            matches ::= parse_specs(
                .source     = source
                .specs      = command.specs
                .start      = start + 1
                .diagnostic = diagnostic
            )!
            result = ..ok(.command = name, .help = false, .matches = ~matches)
            return
        }
    }
    _set_diagnostic(diagnostic, .argument = name, .message = "unknown command")
    result = ..error(.reason = ..unknown_command)
}

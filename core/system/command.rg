..unknown_option
..duplicate_option
..required_option
..unexpected_option_value
..invalid_cli_schema

CliSpec: Type = (
    .name          : StringView,
    .short_name    : StringView  = "",
    .help          : StringView  = "",
    .value_name    : StringView  = "",
    .required      : Bool        = false,
    .repeatable    : Bool        = false,
    .default_value : ?StringView = ..none
)

CliSpec implements ImplicitlyCopyable

CliValue: Type = (.name: StringView, .value: ?StringView)

CliValue implements ImplicitlyCopyable

CliMatches: Type = (
    .options     : DynamicArray#(.t: CliValue),
    .positionals : DynamicArray#(.t: StringView)
)

CliReasons: Type = (
    ..invalid_option,
    ..missing_option_value,
    ..unknown_option,
    ..duplicate_option,
    ..required_option,
    ..unexpected_option_value,
    ..invalid_cli_schema,
    ..out_of_memory
)

-- Specs and results borrow their text. Callers retain both the argument source
-- and schema until matches are destroyed. Every option uses a canonical long
-- name; aliases and defaults are resolved without copying argument bytes.
parse_cli#(
        .t : Type: ArgumentSource
    )(
        .source    : &t,
        .specs     : ArrayViewRO#(.t: CliSpec),
        .start     : UIntNative                 = 0,
        .allocator : $&Allocator                = reach allocator
    ) -> (
        .result : Errable#(CliMatches, CliReasons)
    ) := {
    assume allocator
    count ::= length(&specs).count
    index :: UIntNative = 0

    while index < count {
        spec ::= unwrap_or_abort(.value = get(&specs, .index = index))
        if spec.name.length == 0 or spec.short_name.length > 1 {
            result = ..error(.reason = ..invalid_cli_schema)
            return
        }
        cursor :: UIntNative = 0
        while cursor < spec.name.length {
            byte ::= bytes_get(.view = &spec.name, .index = cursor).byte
            if byte == 61 or byte == 32 or byte == 0 {
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
            cursor = cursor + 1
        }
        previous :: UIntNative = 0
        while previous < index {
            other ::= unwrap_or_abort(.value = get(&specs, .index = previous))
            if [
                other.name == spec.name
                or [spec.short_name.length > 0 and other.short_name == spec.short_name]
            ] {
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
            previous = previous + 1
        }
        index = index + 1
    }

    options ::= DynamicArray#(.t: CliValue)(.capacity = count)!
    positionals ::= DynamicArray#(.t: StringView)(.capacity = 1)!
    parser ::= CliParser#(.t: t)(.source = source, .start = start)

    while true {
        match next($&parser)! {
            ..none { break }
            ..some argument {
                match argument.value {
                    ..positional value {
                        push(.self = $&positionals, .value = value)!
                    }
                    ..option option {
                        found ::= false
                        index = 0
                        while index < count {
                            spec ::= unwrap_or_abort(.value = get(&specs, .index = index))
                            matches :: Bool = option.name == spec.name
                            if option.short { matches = option.name == spec.short_name }
                            if matches {
                                found = true
                                if spec.repeatable == false {
                                    cursor :: UIntNative = 0
                                    while cursor < length(&options).count {
                                        existing ::= unwrap_or_abort(
                                            .value = get(&options, .index = cursor)
                                        )
                                        if existing.name == spec.name {
                                            result = ..error(.reason = ..duplicate_option)
                                            return
                                        }
                                        cursor = cursor + 1
                                    }
                                }
                                value :: ?StringView = ..none
                                if spec.value_name.length > 0 {
                                    value = ..some(
                                        .value = take_value($&parser, .option = option)!
                                    )
                                } else {
                                    match option.value {
                                        ..some _ {
                                            result = ..error(.reason = ..unexpected_option_value)
                                            return
                                        } ..none {}
                                    }
                                }
                                push(
                                    .self  = $&options
                                    .value = CliValue(.name = spec.name, .value = value)
                                )!
                                break
                            }
                            index = index + 1
                        }
                        if found == false {
                            result = ..error(.reason = ..unknown_option)
                            return
                        }
                    }
                }
            }
        }
    }

    index = 0

    while index < count {
        spec ::= unwrap_or_abort(.value = get(&specs, .index = index))
        found ::= false
        cursor :: UIntNative = 0
        while cursor < length(&options).count {
            existing ::= unwrap_or_abort(.value = get(&options, .index = cursor))
            if existing.name == spec.name {
                found = true
                break
            }
            cursor = cursor + 1
        }
        if found == false {
            match spec.default_value {
                ..some entry {
                    defaulted :: ?StringView = ..some(.value = entry.value)
                    push(
                        .self  = $&options
                        .value = CliValue(.name = spec.name, .value = defaulted)
                    )!
                    found = true
                } ..none {}
            }
            if spec.required and found == false {
                result = ..error(.reason = ..required_option)
                return
            }
        }
        index = index + 1
    }

    result = ..ok(.options = ~options, .positionals = ~positionals)
}

write_cli_help(
        .writer  : $&Writer,
        .program : StringView,
        .about   : StringView,
        .specs   : ArrayViewRO#(.t: CliSpec)
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()
    ) := {
    write(writer, .text = about)!
    write(writer, .text = "\nUsage: ")!
    write(writer, .text = program)!
    write(writer, .text = " [OPTIONS] [ARGS]\n\nOptions:\n")!
    index :: UIntNative = 0

    while index < length(&specs).count {
        spec ::= unwrap_or_abort(.value = get(&specs, .index = index))
        write(writer, .text = "  ")!
        if spec.short_name.length > 0 {
            write(writer, .text = "-")!
            write(writer, .text = spec.short_name)!
            write(writer, .text = ", ")!
        }
        write(writer, .text = "--")!
        write(writer, .text = spec.name)!
        if spec.value_name.length > 0 {
            write(writer, .text = " <")!
            write(writer, .text = spec.value_name)!
            write(writer, .text = ">")!
        }
        if spec.required { write(writer, .text = " (required)")! }
        if spec.repeatable { write(writer, .text = " (repeatable)")! }
        write(writer, .text = "  ")!
        write(writer, .text = spec.help)!
        match spec.default_value {
            ..none {} ..some entry {
                write(writer, .text = " [default: ")!
                write(writer, .text = entry.value)!
                write(writer, .text = "]")!
            }
        }
        write(writer, .text = "\n")!
        index = index + 1
    }
}

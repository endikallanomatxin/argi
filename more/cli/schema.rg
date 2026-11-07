..unknown_option
..duplicate_option
..required_option
..unexpected_option_value
..invalid_cli_schema

Spec := (
    .name          : StringView,
    .short_name    : StringView  = "",
    .help          : StringView  = "",
    .value_name    : StringView  = "",
    .required      : Bool        = false,
    .repeatable    : Bool        = false,
    .default_value : ?StringView = ..none
)

implement ImplicitlyCopyable#(Spec) ()

_valid_cli_option_name := (.name: StringView) -> (.ok: Bool = true) {

    index :: UIntNative = 0
    while index < byte_length(&name).count {
        byte ::= bytes_get(.view = &name, .index = index) handle ignored, value { abort }
        if byte <= 32 or byte == 127 or byte == 61 {
            ok = false
            return
        }
        index = index + 1
    }
}

-- Specs and results borrow their text. Callers retain both the argument source
-- and schema until matches are destroyed. Every option uses a canonical long
-- name; aliases and defaults are resolved without copying argument bytes.
-- Names exclude ASCII controls, spaces and '='. Defaults require value options.
parse := #(.t: Type: ArgumentSource#(t)) (
    .source    : &t,
    .specs     : ArrayView#(.t: Spec),
    .start     : UIntNative            = 0,
    .allocator : Virtual#(Allocator)
) -> (.result: Errable#(Matches, Reasons)) {

    assume allocator
    count ::= length(&specs).count
    index :: UIntNative = 0

    while index < count {
        spec ::= get(&specs, .index = index)!
        if byte_length(&spec.name).count == 0 or byte_length(&spec.short_name).count > 1 {
            result = ..error(.reason = ..invalid_cli_schema)
            return
        }
        if [
            _valid_cli_option_name(.name = spec.name).ok == false
            or _valid_cli_option_name(.name = spec.short_name).ok == false
        ] {
            result = ..error(.reason = ..invalid_cli_schema)
            return
        }
        if byte_length(&spec.value_name).count == 0 {
            match spec.default_value {
                ..none {}
                ..some _ {
                    result = ..error(.reason = ..invalid_cli_schema)
                    return
                }
            }
        }
        previous :: UIntNative = 0
        while previous < index {
            other ::= get(&specs, .index = previous)!
            if [
                other.name == spec.name
                or [
                    byte_length(&spec.short_name).count > 0
                    and other.short_name == spec.short_name
                ]
            ] {
                result = ..error(.reason = ..invalid_cli_schema)
                return
            }
            previous = previous + 1
        }
        index = index + 1
    }

    options ::= DynamicArray#(.t: Value)(.capacity = count)!
    positionals ::= DynamicArray#(.t: StringView)(.capacity = 1)!
    parser ::= Parser#(.t: t)(.source = source, .start = start)

    while true {
        match next($&parser)! {
            ..none { break }
            ..some argument {
                match argument.value {
                    ..positional value {
                        push(.self = $&positionals, .value = value, .allocator = allocator)!
                    }
                    ..option option {
                        found ::= false
                        index = 0
                        while index < count {
                            spec ::= get(&specs, .index = index)!
                            matches :: Bool = option.name == spec.name
                            if option.short { matches = option.name == spec.short_name }
                            if matches {
                                found = true
                                if spec.repeatable == false {
                                    cursor :: UIntNative = 0
                                    while cursor < length(&options).count {
                                        existing ::= get(&options, .index = cursor)!
                                        if existing.name == spec.name {
                                            result = ..error(.reason = ..duplicate_option)
                                            return
                                        }
                                        cursor = cursor + 1
                                    }
                                }
                                value :: ?StringView = ..none
                                if byte_length(&spec.value_name).count > 0 {
                                    value = ..some(
                                        .value = take_value($&parser, .option = option)!
                                    )
                                } else {
                                    match option.value {
                                        ..some _ {
                                            result = ..error(
                                                .reason = ..unexpected_option_value
                                            )
                                            return
                                        } ..none {}
                                    }
                                }
                                push(
                                    .self      = $&options
                                    .value     = Value(.name = spec.name, .value = value)
                                    .allocator = allocator
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
        spec ::= get(&specs, .index = index)!
        found ::= false
        cursor :: UIntNative = 0
        while cursor < length(&options).count {
            existing ::= get(&options, .index = cursor)!
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
                        .self      = $&options
                        .value     = Value(.name = spec.name, .value = defaulted)
                        .allocator = allocator
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

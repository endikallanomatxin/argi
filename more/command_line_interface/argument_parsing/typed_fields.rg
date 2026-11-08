-- Configuration functions are specialized identities. Their returned metadata
-- is shared parser input, never part of an argument wrapper's stored layout.
OptionConfig := #(.T: Type) (
    .short_name    : StringView = "",
    .help          : StringView = "",
    .value_name    : StringView = "VALUE",
    .default_value : ?T         = ..none
)

_default_config := #(.T: Type) () -> (.config: OptionConfig#(T)) { config = () }

Option := #(.T: Type, .config: Function = _default_config#(T)) (.value: T)

Positional := #(.T: Type, .config: Function = _default_config#(T)) (.value: T)

Flag := #(.config: Function = _default_config#(Bool)) (.value: Bool)

FieldInfo := (.spec: Spec, .positional: Bool = false)

-- Empty values are used only in an unpublished partial result after failure.
-- They never escape a successful parse or replace a required/defaulted value.
ArgumentValue#(.T: Type): Contract = (
    .parse : (.text: StringView) -> (.result: Errable#(T, (..invalid_argument_value)))
    .empty : () -> (.value: T)
)

ArgumentField#(.Field: Type): Contract = (
    .describe : (.name: StringView) -> (.info: FieldInfo)
    .read     : (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(Field, (..invalid_argument_value, ..required_option))
    )
    .empty : () -> (.field: Field)
)

implement ArgumentValue#(StringView) (
    .parse = (.text: StringView) -> (.result: Errable#(StringView, (..invalid_argument_value))) {
        result = ..ok text
    }
    .empty = () -> (.value: StringView) { value = "" }
)

implement#(.T: Type: ArgumentValue#(T), .config: Function) ArgumentField#(Option#(T, config)) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        metadata ::= invoke#(config)(.args = ())
        required ::= false
        match metadata.default_value { ..none { required = true } ..some _ {} }
        info = (
            .spec = Spec(
                .name       = name
                .short_name = metadata.short_name
                .help       = metadata.help
                .value_name = metadata.value_name
                .required   = required
            )
        )
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(Option#(T, config), (..invalid_argument_value, ..required_option))
    ) {
        match text {
            ..some entry {
                value ::= ArgumentValue#(T).parse(entry.value)!
                result = ..ok(.value = ~value)
                return
            }
            ..none {}
        }
        metadata ::= invoke#(config)(.args = ())
        match metadata.default_value {
            ..some entry { result = ..ok(.value = entry.value) }
            ..none { result = ..error(.reason = ..required_option) }
        }
    }
    .empty = () -> (.field: Option#(T, config)) {
        field = (.value = ArgumentValue#(T).empty())
    }
)

implement#(.T: Type: ArgumentValue#(T), .config: Function) ArgumentField#(
    Positional#(T, config)
) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        metadata ::= invoke#(config)(.args = ())
        info = (
            .spec = Spec(
                .name = name, .help = metadata.help, .value_name = metadata.value_name
            )
            .positional = true
        )
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(Positional#(T, config), (..invalid_argument_value, ..required_option))
    ) {
        match text {
            ..some entry {
                value ::= ArgumentValue#(T).parse(entry.value)!
                result = ..ok(.value = ~value)
                return
            }
            ..none {}
        }
        metadata ::= invoke#(config)(.args = ())
        match metadata.default_value {
            ..some entry { result = ..ok(.value = entry.value) }
            ..none { result = ..error(.reason = ..required_option) }
        }
    }
    .empty = () -> (.field: Positional#(T, config)) {
        field = (.value = ArgumentValue#(T).empty())
    }
)

implement#(.config: Function) ArgumentField#(Flag#(config)) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        metadata ::= invoke#(config)(.args = ())
        info = (
            .spec = Spec(.name = name, .short_name = metadata.short_name, .help = metadata.help)
        )
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(Flag#(config), (..invalid_argument_value, ..required_option))
    ) {
        result = ..ok(.value = present)
    }
    .empty = () -> (.field: Flag#(config)) { field = (.value = false) }
)

_numeric_argument := #(.T: Type, .F: Function) (.text: StringView) -> (
    .result : Errable#(T, (..invalid_argument_value))
) {
    parsed ::= invoke#(F)(.args = (.text = text)) handle ignored, recovered {
        result = ..error(.reason = ..invalid_argument_value)
        return
    }
    result = ..ok parsed
}

implement ArgumentValue#(Bool) (
    .parse = (.text: StringView) -> (.result: Errable#(Bool, (..invalid_argument_value))) {
        if text == "true" {
            result = ..ok true
        } else {
            if text == "false" {
                result = ..ok false
            } else {
                result = ..error(.reason = ..invalid_argument_value)
            }
        }
    }
    .empty = () -> (.value: Bool = false) {}
)

implement ArgumentValue#(Int8) (
    .parse = _numeric_argument#(Int8, parse_int8)
    .empty = () -> (.value: Int8 = 0) {}
)

implement ArgumentValue#(Int16) (
    .parse = _numeric_argument#(Int16, parse_int16)
    .empty = () -> (.value: Int16 = 0) {}
)

implement ArgumentValue#(Int32) (
    .parse = _numeric_argument#(Int32, parse_int32)
    .empty = () -> (.value: Int32 = 0) {}
)

implement ArgumentValue#(Int64) (
    .parse = _numeric_argument#(Int64, parse_int64)
    .empty = () -> (.value: Int64 = 0) {}
)

implement ArgumentValue#(UInt8) (
    .parse = _numeric_argument#(UInt8, parse_uint8)
    .empty = () -> (.value: UInt8 = 0) {}
)

implement ArgumentValue#(UInt16) (
    .parse = _numeric_argument#(UInt16, parse_uint16)
    .empty = () -> (.value: UInt16 = 0) {}
)

implement ArgumentValue#(UInt32) (
    .parse = _numeric_argument#(UInt32, parse_uint32)
    .empty = () -> (.value: UInt32 = 0) {}
)

implement ArgumentValue#(UInt64) (
    .parse = _numeric_argument#(UInt64, parse_uint64)
    .empty = () -> (.value: UInt64 = 0) {}
)

implement ArgumentValue#(UIntNative) (
    .parse = _numeric_argument#(UIntNative, parse_uintnative)
    .empty = () -> (.value: UIntNative = 0) {}
)

implement ArgumentValue#(Float32) (
    .parse = _numeric_argument#(Float32, parse_float32)
    .empty = () -> (.value: Float32 = 0) {}
)

implement ArgumentValue#(Float64) (
    .parse = _numeric_argument#(Float64, parse_float64)
    .empty = () -> (.value: Float64 = 0) {}
)

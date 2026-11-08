-- Metadata participates in type specialization; instances store only the value.
Option := #(
    .T             : Type,
    .short_name    : StringView = "",
    .help          : StringView = "",
    .value_name    : StringView = "VALUE",
    .default_value : ?T         = ..none
) (.value: T)

Positional := #(
    .T             : Type,
    .help          : StringView = "",
    .value_name    : StringView = "VALUE",
    .default_value : ?T         = ..none
) (.value: T)

Flag := #(.short_name: StringView = "", .help: StringView = "") (.value: Bool)

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

implement#(
    .T             : Type: ArgumentValue#(T),
    .short_name    : StringView,
    .help          : StringView,
    .value_name    : StringView,
    .default_value : ?T
) ArgumentField#(Option#(T, short_name, help, value_name, default_value)) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        required ::= false
        match default_value { ..none { required = true } ..some _ {} }
        info = (
            .spec = Spec(
                .name       = name
                .short_name = short_name
                .help       = help
                .value_name = value_name
                .required   = required
            )
        )
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(
            Option#(T, short_name, help, value_name, default_value),
            (..invalid_argument_value, ..required_option)
        )
    ) {
        match text {
            ..some entry {
                value ::= ArgumentValue#(T).parse(entry.value)!
                result = ..ok(.value = ~value)
                return
            }
            ..none {}
        }
        match default_value {
            ..some entry { result = ..ok(.value = entry.value) }
            ..none { result = ..error(.reason = ..required_option) }
        }
    }
    .empty = () -> (.field: Option#(T, short_name, help, value_name, default_value)) {
        field = (.value = ArgumentValue#(T).empty())
    }
)

implement#(
    .T: Type: ArgumentValue#(T), .help: StringView, .value_name: StringView, .default_value: ?T
) ArgumentField#(Positional#(T, help, value_name, default_value)) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        info = (
            .spec       = Spec(.name = name, .help = help, .value_name = value_name)
            .positional = true
        )
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(
            Positional#(T, help, value_name, default_value),
            (..invalid_argument_value, ..required_option)
        )
    ) {
        match text {
            ..some entry {
                value ::= ArgumentValue#(T).parse(entry.value)!
                result = ..ok(.value = ~value)
                return
            }
            ..none {}
        }
        match default_value {
            ..some entry { result = ..ok(.value = entry.value) }
            ..none { result = ..error(.reason = ..required_option) }
        }
    }
    .empty = () -> (.field: Positional#(T, help, value_name, default_value)) {
        field = (.value = ArgumentValue#(T).empty())
    }
)

implement#(.short_name: StringView, .help: StringView) ArgumentField#(Flag#(short_name, help)) (
    .describe = (.name: StringView) -> (.info: FieldInfo) {
        info = (.spec = Spec(.name = name, .short_name = short_name, .help = help))
    }
    .read = (.text: ?StringView, .present: Bool) -> (
        .result : Errable#(
            Flag#(short_name, help), (..invalid_argument_value, ..required_option)
        )
    ) {
        result = ..ok(.value = present)
    }
    .empty = () -> (.field: Flag#(short_name, help)) { field = (.value = false) }
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

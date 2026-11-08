-- Optional metadata on a choice payload. Ordinary record payloads need no wrapper.
Subcommand := #(
    .Args        : Type,
    .is_default  : Bool       = false,
    .long_alias  : StringView = "",
    .short_alias : StringView = ""
) (.arguments: Args)

SubcommandInfo := (
    .name        : StringView,
    .is_default  : Bool        = false,
    .is_help     : Bool        = false,
    .long_alias  : StringView  = "",
    .short_alias : StringView  = ""
)

SubcommandPayload#(.Payload: Type): Contract = (
    .Arguments : Type
    .describe  : (.name: StringView) -> (.info: SubcommandInfo)
    .wrap      : (.arguments: Arguments) -> (.payload: Payload)
    -- Called only for the unique payload whose metadata sets is_help.
    .from_help : (.command: StringView) -> (.payload: Payload)
)

implement#(.Payload: Type) SubcommandPayload#(Payload) (
    .Arguments : Type = Payload
    .describe  = (.name: StringView) -> (.info: SubcommandInfo) { info = (.name = name) }
    .wrap      = (.arguments: Arguments) -> (.payload: Payload) { payload = ~arguments }
    .from_help = (.command: StringView) -> (.payload: Payload) { abort }
)

implement#(.Args: Type, .is_default: Bool, .long_alias: StringView, .short_alias: StringView) SubcommandPayload#(
    Subcommand#(Args, is_default, long_alias, short_alias)
) (
    .Arguments : Type = SubcommandPayload#(Args).Arguments
    .describe  = (.name: StringView) -> (.info: SubcommandInfo) {
        info = SubcommandPayload#(Args).describe(name)
        info.is_default = is_default
        if long_alias != "" { info.long_alias = long_alias }
        if short_alias != "" { info.short_alias = short_alias }
    }
    .wrap = (.arguments: Arguments) -> (
        .payload : Subcommand#(Args, is_default, long_alias, short_alias)
    ) { payload = (.arguments = SubcommandPayload#(Args).wrap(~arguments)) }
    .from_help = (.command: StringView) -> (
        .payload : Subcommand#(Args, is_default, long_alias, short_alias)
    ) {
        payload = (.arguments = SubcommandPayload#(Args).from_help(command))
    }
)

implement ImplicitlyCopyable#(SubcommandInfo) ()

-- Help is an ordinary command payload with parser-recognized construction evidence.
_HelpArguments := (
    .command : Positional#(
        StringView, .help = "Command to describe", .default_value = ..some(.value = "")
    )
)

implement SubcommandPayload#(Help) (
    .Arguments : Type = _HelpArguments
    .describe  = (.name: StringView) -> (.info: SubcommandInfo) {
        info = (.name = name, .is_help = true, .long_alias = "help", .short_alias = "h")
    }
    .wrap = (.arguments: Arguments) -> (.payload: Help) {
        payload = (.command = arguments.command.value)
    }
    .from_help = (.command: StringView) -> (.payload: Help) { payload = (.command = command) }
)

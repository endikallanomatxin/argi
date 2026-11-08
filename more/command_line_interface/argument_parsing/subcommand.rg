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
    .long_alias  : StringView  = "",
    .short_alias : StringView  = ""
)

SubcommandPayload#(.Payload: Type): Contract = (
    .Arguments : Type
    .describe  : (.name: StringView) -> (.info: SubcommandInfo)
    .wrap      : (.arguments: Arguments) -> (.payload: Payload)
)

implement#(.Payload: Type) SubcommandPayload#(Payload) (
    .Arguments : Type = Payload
    .describe  = (.name: StringView) -> (.info: SubcommandInfo) { info = (.name = name) }
    .wrap      = (.arguments: Arguments) -> (.payload: Payload) { payload = ~arguments }
)

implement#(.Args: Type, .is_default: Bool, .long_alias: StringView, .short_alias: StringView) SubcommandPayload#(
    Subcommand#(Args, is_default, long_alias, short_alias)
) (
    .Arguments : Type = Args
    .describe  = (.name: StringView) -> (.info: SubcommandInfo) {
        info = (
            .name        = name
            .is_default  = is_default
            .long_alias  = long_alias
            .short_alias = short_alias
        )
    }
    .wrap = (.arguments: Args) -> (
        .payload : Subcommand#(Args, is_default, long_alias, short_alias)
    ) { payload = (.arguments = ~arguments) }
)

implement ImplicitlyCopyable#(SubcommandInfo) ()

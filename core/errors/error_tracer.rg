ErrorTracer#(.Tracer: Type): Contract = (
    .add_context   : (.self: $&Tracer, .location: SourceLocationId, .context: StringView) -> () where {}
    .reset_context : (.self: $&Tracer) -> () where {}
    .report        : (.self: $&Tracer, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) where {
        on result ..ok {}
    }
)

add_context := (
    .context      : StringView,
    .location     : SourceLocationId         = error_location_id(),
    .error_tracer : $&Virtual#(ErrorTracer),
) -> () {
    ErrorTracer#().add_context(.self = error_tracer, .location = location, .context = context)
}

add_context_text := (
    .context      : &CChar,
    .location     : SourceLocationId         = error_location_id(),
    .error_tracer : $&Virtual#(ErrorTracer),
) -> () {
    ErrorTracer#(
    ).add_context(
        .self     = error_tracer
        .location = location
        .context  = _trusted_c_string_view(.text = context).view
    )
}

capture_error_tracer := (.location: SourceLocationId, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .tracer : $&Virtual#(ErrorTracer)
) {
    add_context(.context = "", .location = location, .error_tracer = error_tracer)
    tracer = error_tracer
}

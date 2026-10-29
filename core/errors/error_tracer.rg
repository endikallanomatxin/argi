ErrorTracer#(.Tracer: Type): Contract = (
    .add_context   : (.self: $&Tracer, .location: SourceLocationId, .context: StringView) -> () where {}
    .reset_context : (.self: $&Tracer) -> () where {}
    .report        : (
        .self         : $&Tracer,
        .writer       : $&Virtual#(.contract: Writer),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
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

-- Propagation binds the original capability explicitly. The text/view
-- helpers keep length-delimited views separate from zero-terminated text.
_add_error_context := (
    .tracer: $&Virtual#(ErrorTracer), .location: SourceLocationId, .context: StringView
) -> () {
    add_context(.context = context, .location = location, .error_tracer = tracer)
}

_add_error_context_text := (
    .tracer: $&Virtual#(ErrorTracer), .location: SourceLocationId, .context: &CChar
) -> () {
    add_context_text(.context = context, .location = location, .error_tracer = tracer)
}

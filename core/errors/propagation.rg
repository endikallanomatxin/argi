-- Context propagation is an ordinary checked call on the error branch. The
-- adapter retains an existing tracer or explicitly acquires the caller's one.
_TracePropagation#(.Payload: Type, .Context: Type): Contract = (
    .Result    : Type
    .propagate : (
        .error        : Payload,
        .context      : Context,
        .location     : SourceLocationId,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result)
)

trace_error := #(.Payload: Type, .Context: Type) (
    .error        : Payload,
    .context      : Context,
    .location     : SourceLocationId        = error_location_id(),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: _TracePropagation#(Payload, Context).Result) {
    result = _TracePropagation#(
        Payload, Context
    ).propagate(
        .error = error, .context = context, .location = location, .error_tracer = error_tracer
    )
}

implement#(.Reasons: Type) _TracePropagation#(Error#(Reasons), StringView) (
    .Result    : Type = Errable#(Void, Reasons, ErrorWithTrace#(Reasons))
    .propagate = (
        .error        : Error#(Reasons),
        .context      : StringView,
        .location     : SourceLocationId,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        tracer ::= error_tracer
        add_context(.context = context, .location = location, .error_tracer = tracer)
        result = ..error(.reason = error.reason, .tracer = tracer)
    }
)

implement#(.Reasons: Type) _TracePropagation#(Error#(Reasons), &CChar) (
    .Result    : Type = Errable#(Void, Reasons, ErrorWithTrace#(Reasons))
    .propagate = (
        .error        : Error#(Reasons),
        .context      : &CChar,
        .location     : SourceLocationId,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        tracer ::= error_tracer
        add_context_text(.context = context, .location = location, .error_tracer = tracer)
        result = ..error(.reason = error.reason, .tracer = tracer)
    }
)

implement#(.Reasons: Type) _TracePropagation#(ErrorWithTrace#(Reasons), StringView) (
    .Result    : Type = Errable#(Void, Reasons, ErrorWithTrace#(Reasons))
    .propagate = (
        .error        : ErrorWithTrace#(Reasons),
        .context      : StringView,
        .location     : SourceLocationId,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        tracer ::= error.tracer
        add_context(.context = context, .location = location, .error_tracer = tracer)
        result = ..error(.reason = error.reason, .tracer = tracer)
    }
)

implement#(.Reasons: Type) _TracePropagation#(ErrorWithTrace#(Reasons), &CChar) (
    .Result    : Type = Errable#(Void, Reasons, ErrorWithTrace#(Reasons))
    .propagate = (
        .error        : ErrorWithTrace#(Reasons),
        .context      : &CChar,
        .location     : SourceLocationId,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        tracer ::= error.tracer
        add_context_text(.context = context, .location = location, .error_tracer = tracer)
        result = ..error(.reason = error.reason, .tracer = tracer)
    }
)

Error := #(.reasons: Type) (.reason: reasons)

ErrorWithTrace := #(.reasons: Type) (
    .reason : reasons
    .tracer : $&Virtual#(ErrorTracer) = capture_error_tracer(.location = error_location_id())
)

Errable := #(.t: Type, .reasons: Type, .error_type: Type = Error#(reasons)) (
    ..ok t
    ..error error_type
)

unwrap_or_abort := #(.t: Type, .reasons: Type, .error_type: Type) (
    .value : Errable#(t, reasons, error_type)
) -> (.result: t) {
    match value {
        ..ok ~payload { result = ~payload }
        ..error _ { abort }
    }
}

-- Build a reason-only failure with an inferred reason type. Passing the reason
-- of a traced error here is an explicit decision to leave its diagnostics behind.
error_result := #(.Reasons: Type) (.reason: Reasons) -> (.result: Errable#(Void, Reasons)) {
    result = ..error(.reason = reason)
}

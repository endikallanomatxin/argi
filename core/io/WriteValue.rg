-- One operation identity covers values written to a destination. Participants
-- select the result protocol; expected output types never select evidence.
WriteValue#(.Stream: Type, .Value: Type): Contract = (
    .Result      : Type
    .write_value : (.self: $&Stream, .value: Value, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Result
    )
)

write := #(.Value: Type, .Stream: Type: WriteValue#(Stream, Value)) (
    .self: $&Stream, .value: Value, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: WriteValue#(Stream, Value).Result) {
    assume error_tracer
    result = ~WriteValue#(Stream, Value).write_value(.self = self, .value = ~value)
}

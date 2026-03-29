ErrorTraceEntry : Type = (
    .line: Int32
    .column: Int32
    .context: &Char
)

ErrorTrace : Type = (
    .entries: DynamicArray#(.t: ErrorTraceEntry)
)

Error#(.reason: Type) : Type = (
    .reason: reason
    .trace: ErrorTrace
)

Errable #(.t: Type, .e: Type) : Type = (
    ..ok(.value: t)
    ..error(
        .reason: e
        .trace: ErrorTrace
    )
)

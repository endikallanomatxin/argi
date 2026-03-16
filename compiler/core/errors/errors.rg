Errable #(.t: Type, .e: Type) : Type = (
    ..ok(.value: t)
    ..error(.value: e)
)

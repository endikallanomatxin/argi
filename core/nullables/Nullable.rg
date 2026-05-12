Nullable #(.t: Type) : Type = (
    =..none
    ..some(.value: t)
)

unwrap_or #(.t: Type) (
    .value: Nullable#(.t: t),
    .default: t,
) -> (.result: t) := {
    match value {
        ..some ~ payload {
            result = payload.value
            return
        }
        ..none {
        }
    }

    result = default
}

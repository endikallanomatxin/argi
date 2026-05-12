ReachedIndexSource : Type = (
    .unused: Int32
)

operator get[] #(.t: Type) (
    .self: &ReachedIndexSource,
    .index: UIntNative,
    .value: t = #reach value,
) -> (.out: t) := {
    out = value
}

main() -> (.status_code: Int32) := {
    source :: ReachedIndexSource = (.unused = 0)
    value :: Int32 = 42

    status_code = source[0]
}

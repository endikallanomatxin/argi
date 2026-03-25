Direction : Type = (
    ..north,
    ..south,
)

main () -> (.status_code: Int32) := {
    value : Direction = ..south

    match value {
        ..north {
            status_code = 1
        }
        ..south {
            status_code = 0
        }
    }
}

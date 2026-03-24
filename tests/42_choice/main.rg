Direction : Type = (
    ..north,
    ..east,
    ..south,
    ..west,
)

main () -> (.status_code: Int32) := {
    dir : Direction = ..south

    if dir == ..south {
        status_code = 0
    } else {
        status_code = 1
    }
}

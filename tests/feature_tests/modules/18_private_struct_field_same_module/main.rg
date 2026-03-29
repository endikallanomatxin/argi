Point : Type = (
    ._hidden: Int32
    .visible: Int32
)

main () -> (.status_code: Int32) := {
    point :: Point = (
        ._hidden = 19,
        .visible = 23,
    )
    status_code = point._hidden + point.visible
}

Point : Type = (
    ._hidden: Int32
    .visible: Int32
)

make_point() -> (.point: Point) := {
    point = (
        ._hidden = 4,
        .visible = 8,
    )
}

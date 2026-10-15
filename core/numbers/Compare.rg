Ordering: Type = (..less, ..equal, ..greater, ..unordered)

Compare#(.Left: Type, .Right: Type): Contract = (
    .compare : (.left: Left, .right: Right) -> (.order: Ordering)
)

CompareRelations#(.Left: Type, .Right: Type): Contract = (
    Compare#(Left, Right)
    .less_than             : (.left: Left, .right: Right) -> (.ok: Bool)
    .less_than_or_equal    : (.left: Left, .right: Right) -> (.ok: Bool)
    .greater_than          : (.left: Left, .right: Right) -> (.ok: Bool)
    .greater_than_or_equal : (.left: Left, .right: Right) -> (.ok: Bool)
)

implement#(.Left: Type: Compare#(Left, Right), .Right: Type) CompareRelations#(Left, Right) (
        .less_than = (
                .left  : Left,
                .right : Right
            ) -> (
                .ok : Bool
            ) {
            ok = is_less_than(Compare#(Left, Right).compare(.left = ~left, .right = ~right).order).ok
        }
        .less_than_or_equal = (
                .left  : Left,
                .right : Right
            ) -> (
                .ok : Bool
            ) {
            ok = is_less_than_or_equal(
                Compare#(Left, Right).compare(.left = ~left, .right = ~right).order
            ).ok
        }
        .greater_than = (
                .left  : Left,
                .right : Right
            ) -> (
                .ok : Bool
            ) {
            ok = is_greater_than(
                Compare#(Left, Right).compare(.left = ~left, .right = ~right).order
            ).ok
        }
        .greater_than_or_equal = (
                .left  : Left,
                .right : Right
            ) -> (
                .ok : Bool
            ) {
            ok = is_greater_than_or_equal(
                Compare#(Left, Right).compare(.left = ~left, .right = ~right).order
            ).ok
        }
    )

is_less_than(.order: Ordering) -> (.ok: Bool) := { ok = order == ..less }

is_less_than_or_equal(.order: Ordering) -> (.ok: Bool) := {
    ok = order == ..less or order == ..equal
}

is_greater_than(.order: Ordering) -> (.ok: Bool) := { ok = order == ..greater }

is_greater_than_or_equal(.order: Ordering) -> (.ok: Bool) := {
    ok = [
        order == ..greater
        or order == ..equal
    ]
}

TotalOrder#(.Left: Type, .Right: Type): Contract = (Compare#(Left, Right))

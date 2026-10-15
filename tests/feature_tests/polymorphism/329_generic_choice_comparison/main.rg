OtherOrdering: Type = (..greater, ..less)

is_less#(.T: Type)(.order: T) -> (.ok: Bool) := { ok = ..less == order }

is_before#(.T: Type)(.marker: T, .order: Ordering) -> (.ok: Bool) := {
    ok = order == ..less or ..greater != order
}

main() -> () := {
    other: OtherOrdering = ..less
    if is_less#(OtherOrdering)(other).ok == false { abort }
    less: Ordering = ..less
    if is_less#(Ordering)(less).ok == false { abort }
    greater: Ordering = ..greater
    if is_before#(Int32)(1, less).ok == false { abort }
    if is_before#(Int32)(1, greater).ok { abort }
}

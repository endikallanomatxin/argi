Indexable#(T) : Abstract = (
    operator get[] (&_, Int) -> (T)
)


List#(t) : Abstract = [
    ---
    A list is any collection that can be indexable.
    ---
    Indexable#(t)

    operator get[]
    operator set[]
    length() : Int
    ...
]

Index : Type = UInt64  -- 1 based index

ListAlignment : Type = [
    ..smallest_power_of_two
    ..compact
    ..custom(n: Int)
]


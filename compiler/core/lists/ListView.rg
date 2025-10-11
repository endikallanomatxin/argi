ListView : Type = (
    -- A ListView is a lightweight descriptor for a window into an indexable collection.
    .start  : UInt64
    .length : UInt64
)

view#(.list_value_type: Type) (
    .list: Indexable#(.t: list_value_type),
    .from: UInt64,
    .to: UInt64,
) -> (.view: ListView) := {
    zero :: UInt64 = 0

    if to < from {
        -- Invalid range, return an empty view.
        view.start = zero
        view.length = zero
        return
    }

    list_length : UInt64 = length(.value=list)
    to_mut :: UInt64 = to

    if from >= list_length {
        -- Start index is out of bounds, return an empty view.
        view.start = zero
        view.length = zero
        return
    }

    if to_mut >= list_length {
        -- Adjust 'to' to the last valid index.
        to_mut = list_length - 1
    }

    actual_to : UInt64 = to_mut

    view.start = from
    view.length = actual_to - from + 1
}

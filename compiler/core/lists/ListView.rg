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

    -- TODO: Implement error handling for invalid ranges.

    if to < from {
        -- Invalid range, return an empty view.
        view = (
            .start = 0,
            .length = 0,
        )
        return
    }

    list_length : UInt64 = length(.value=list)
    to_mut :: UInt64 = to

    if from >= list_length {
        -- Start index is out of bounds, return an empty view.
        view = (
            .start = 0,
            .length = 0,
        )
        return
    }

    if to_mut >= list_length {
        -- Adjust 'to' to the last valid index.
        to_mut = list_length - 1
    }

    actual_to : UInt64 = to_mut

    view = (
        .start = from,
        .length = actual_to - from + 1,
    )
}

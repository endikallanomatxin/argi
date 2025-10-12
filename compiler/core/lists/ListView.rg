ListView#(.list_type: Type, .list_value_type: Type) : Type = (
    -- A ListView is a lightweight descriptor for a window into an indexable collection.
    .data   : $&list_type
    .start  : Int32
    .length : Int32
)

view#(.list_type: Type, .list_value_type: Type) (
    .list: list_type,
    .from: Int32,
    .to: Int32,
) -> (.view: ListView#(.list_type: list_type, .list_value_type: list_value_type)) := {
    zero :: Int32 = 0

    if to < from {
        -- Invalid range, return an empty view.
        view.start = zero
        view.length = zero
        return
    }

    list_length : Int32 = length(.value=list)
    to_mut :: Int32 = to

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

    actual_to : Int32 = to_mut

    view.data = $&list
    view.start = from
    view.length = actual_to - from + 1
}

operator get[] #(.list_type: Type, .list_value_type: Type) (
    .self: &ListView#(.list_type: list_type, .list_value_type: list_value_type)
    .index: Int32
) -> (.value: list_value_type) := {
    -- if index >= view.length {
    --     error("Index out of bounds")
    -- }

    view_value :: ListView#(.list_type=list_type, .list_value_type=list_value_type) = self&

    offset : Int32 = view_value.start + index

    snapshot :: list_type = view_value.data&

    value = snapshot[offset]
}

operator set[] #(.list_type: Type, .list_value_type: Type) (
    .self: $&ListView#(.list_type: list_type, .list_value_type: list_value_type)
    .index: Int32
    .value: list_value_type
) -> () := {
    -- if index >= view.length {
    --     error("Index out of bounds")
    -- }

    view_value :: ListView#(.list_type=list_type, .list_value_type=list_value_type) = self&

    offset : Int32 = view_value.start + index

    snapshot :: list_type = view_value.data&

    snapshot[offset] = value
    view_value.data& = snapshot
}

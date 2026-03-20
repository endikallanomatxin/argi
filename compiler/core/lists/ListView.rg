ListViewRO#(.list_type: Type, .list_value_type: Type) : Type = (
    --
    -- Lightweight non-owning read-only window into a contiguous collection.
    --
    -- It borrows the backing collection and tracks a subrange.
    -- Copying the view copies only this descriptor.
    --
    .list   : &list_type
    .start  : UIntNative
    .length : UIntNative
)

ListViewRW#(.list_type: Type, .list_value_type: Type) : Type = (
    --
    -- Lightweight non-owning mutable window into a contiguous collection.
    --
    -- It borrows the backing collection mutably and tracks a subrange.
    -- Copying the view copies only this descriptor.
    --
    .list   : $&list_type
    .start  : UIntNative
    .length : UIntNative
)

get#(.list_type: Type, .list_value_type: Type) (
    .self: &ListViewRO#(.list_type: list_type, .list_value_type: list_value_type),
    .offset: UIntNative
) -> (.value: list_value_type) := {
    view :: ListViewRO#(.list_type: list_type, .list_value_type: list_value_type) = self&
    value = view.list&[view.start + offset]
}

get#(.list_type: Type, .list_value_type: Type) (
    .self: &ListViewRW#(.list_type: list_type, .list_value_type: list_value_type),
    .offset: UIntNative
) -> (.value: list_value_type) := {
    view :: ListViewRW#(.list_type: list_type, .list_value_type: list_value_type) = self&
    value = view.list&[view.start + offset]
}

set#(.list_type: Type, .list_value_type: Type) (
    .self: $&ListViewRW#(.list_type: list_type, .list_value_type: list_value_type),
    .offset: UIntNative,
    .value: list_value_type
) -> () := {
    view :: ListViewRW#(.list_type: list_type, .list_value_type: list_value_type) = self&
    view.list&[view.start + offset] = value
}

ListView#(.t: Type) : Type = (
    --
    -- Lightweight non-owning read-only view over contiguous elements.
    --
    -- A `ListView` does not own the memory it points to and does not extend
    -- the lifetime of any backing allocation.
    --
    -- Copying a `ListView` only copies the descriptor. It never creates
    -- ownership of the underlying data.
    --
    .data   : &t
    .length : UIntNative
)

MutableListView#(.t: Type) : Type = (
    --
    -- Lightweight non-owning mutable view over contiguous elements.
    --
    -- This should stay a plain borrowed view. Mutable access does not imply
    -- ownership; it only means the referenced memory may be edited while the
    -- backing owner remains valid.
    --
    .data   : $&t
    .length : UIntNative
)

operator get[] #(.t: Type) (
    .self: &ListView#(.t: t)
    .index: UIntNative
) -> (.value: t) := {
    value = self.data[index]
}

operator get[] #(.t: Type) (
    .self: &MutableListView#(.t: t)
    .index: UIntNative
) -> (.value: t) := {
    value = self.data[index]
}

operator set[] #(.t: Type) (
    .self: $&MutableListView#(.t: t)
    .index: UIntNative
    .value: t
) -> () := {
    self.data[index] = value
}

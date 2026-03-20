StringViewRO : Type = (
    --
    -- Lightweight non-owning read-only view into a string.
    --
    -- Copying the view copies only the descriptor. It never copies the string
    -- contents and does not extend the lifetime of the backing owner.
    --
    .string : &String
    .start  : UIntNative
    .length : UIntNative
)

StringViewRW : Type = (
    --
    -- Lightweight non-owning mutable view into a string.
    --
    -- This should stay an explicit borrowed window. Mutable access does not
    -- imply ownership of the underlying storage.
    --
    .string : $&String
    .start  : UIntNative
    .length : UIntNative
)

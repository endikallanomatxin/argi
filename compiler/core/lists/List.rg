Indexable#(.t : Type) : Abstract = (
    length (.self: Self) -> (.n: UIntNative)
    operator get[] (.self: &Self, .i: UIntNative) -> (.value: t)
)

IndexableMutable#(.t: Type) : Abstract = (
    length (.self: Self) -> (.n: UIntNative)
    operator get[] (.self: &Self, .i: UIntNative) -> (.value: t)
    operator set[] (.self: $&Self, .i: UIntNative, .value: t) -> ()
)

Resizable#(.t: Type) : Abstract = (
    length (.self: Self) -> (.n: UIntNative)
    operator get[] (.self: &Self, .i: UIntNative) -> (.value: t)
    operator set[] (.self: $&Self, .i: UIntNative, .value: t) -> ()
    push (.self: $&Self, .value: t) -> ()
    pop (.self: $&Self) -> (.value: t)
    insert (.self: $&Self, .i: UIntNative, .value: t) -> ()
)

-- List#(.t: Type) : Abstract = (
--     ---
--     A list is any collection that can be indexable.
--     ---
--     Indexable#(.t: t)
-- 
--     operator get[]
--     operator set[]
--     length() : UIntNative
--     ...
-- )
-- 
-- Index : Type = UIntNative  -- 1 based index
-- 
-- ListAlignment : Type = (
--     ..smallest_power_of_two
--     ..compact
--     ..custom(.n: UIntNative)
-- )
-- 

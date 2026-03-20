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



-- List#(t) : Abstract = [
--     ---
--     A list is any collection that can be indexable.
--     ---
--     Indexable#(t)
-- 
--     operator get[]
--     operator set[]
--     length() : Int
--     ...
-- ]
-- 
-- Index : Type = UInt64  -- 1 based index
-- 
-- ListAlignment : Type = [
--     ..smallest_power_of_two
--     ..compact
--     ..custom(n: Int)
-- ]
-- 

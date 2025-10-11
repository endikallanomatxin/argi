Indexable#(.t : Type) : Abstract = (
    length (.self: Self) -> (.n: UInt64)
    operator get[] (.s: &Self, .i: UInt) -> (.v: t)
)

IndexableMutable#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
  operator set[] (.self: Self, .i: UInt64, .value: T) -> ()
)

Resizable#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
  operator set[] (.self: Self, .i: UInt64, .value: T) -> ()

  push (.self: Self, .value: T) -> (),
  pop (.self: Self) -> (.value: T),
  insert (.self: Self, .i: UInt64, .value: T) -> ()
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

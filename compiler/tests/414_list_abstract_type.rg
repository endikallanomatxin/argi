-- Move this to core

List#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
)

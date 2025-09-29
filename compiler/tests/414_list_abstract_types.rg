-- Indexable#(T) → lectura indexada: len() y get[].
-- IndexableMutable#(T) → añade set[].
-- Resizable#(T) → añade push, pop, insert, … (solo para los dinámicos).

-- TODO: Pensar como hacer que sean más intuitivas para los nuevos.
-- Rollo List#(T) era más claro. Así está mejor, pero menos claro.

-- Move this to core

Indexable#(.T: Type) : Abstract = (
  length (.self: Self) -> (.n: UInt64),
  operator get[] (.self: Self, .i: UInt64) -> (.value: T)
)

IndexableMutable#(.T: Type) : Abstract = (
  Indexable#(T)
  operator set[] (.self: Self, .i: UInt64, .value: T) -> ()
)

Resizable#(.T: Type) : Abstract = (
  IndexableMutable#(T)
  push (.self: Self, .value: T) -> (),
  pop (.self: Self) -> (.value: T),
  insert (.self: Self, .i: UInt64, .value: T) -> ()
)


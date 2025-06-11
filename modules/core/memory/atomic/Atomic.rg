Atomic<t: Type> : Type = [
	-- Wrapper to prevent data races
	._data: t
]

-- Carga atómica
load(self: &Atomic<T>, order: AtomicOrder) := T {
    atomicLoad(T, &self._data, order)  -- builtin
}

-- Almacenamiento atómico
store(self: &Atomic<T>, value: T, order: AtomicOrder) := {
    atomicStore(T, &self._data, value, order)  -- builtin
}

-- Intercambio atómico (exchange)
swap(self: &Atomic<T>, operand: T, order: AtomicOrder) := T {
    return atomicRmw(T, &self._data, AtomicRmwOp.Xchg, operand, order)  -- builtin
}


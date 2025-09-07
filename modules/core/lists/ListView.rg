ListView#(.t: Type) : Type = [
	---
	A ListView is a view over a List.
	It does not own the data, just references it.
	It is similar to a slice in Rust or Go.
	---
	._data      : &Byte
	._data_type : Type      = t
	._length    : UInt64
	._alignment : Alignment = ..Default
]

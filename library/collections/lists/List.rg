List<t> : Abstract = [
    ---
    A list is any collection that can be indexable.
    ---

    operator get[]
    operator set[]
    length() : Int
    ...
]

Index : Type = UInt64  -- 1 based index

ListAlignment : Type = [
    ..smallest_power_of_two
    ..compact
    ..custom(n: Int)
]

builtin StackByteArray<N> : Type
---
This holds a contiguous memory in the stack that is N bits long.
It directly maps to what results from alloca in LLVM.
It allows for get[] and set[] but
does not implement any of the list abstrations.
In general, don't use it. Use a StaticArray<Bit, n> instead

TODO: Think if it would be better to support specialized syntax for this
as many other languajes do.
---


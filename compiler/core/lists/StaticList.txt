StaticList#(.t: Type, .n: Int) : abstract = []

List#(.t) canbe StaticList#(.t, _)


StackArray#(.t, .n) : Type = (
    ---
    This is a stack allocated array.
    Similar to the default array in C or zig, when not using malloc.
    In this language, declaration of a StackArray has to be intentional.
    ---
    ._data      : &Byte
    ._data_type : t
    ._length    : UInt64    = n  -- Igual 64 es demasiado?
    ._alignment : Alignment = ..Default
)

StaticList#(t, n) canbe StackArray#(t, n)
Indexable#(t)     canbe StackArray#(t, n)
List#(t)          canbe StackArray#(t, n)

operator get[] (&a: StackArray#(.t, .n), .i:Int) -> (.v: t) := {
    if i < 1 or i > N {
        panic("Index out of bounds")
    }

    -- Read from i to i + sizeof(T)
    offset := (i - 1) * @sizeOf(T)
    ptr : &t = &a._data + offset

    return ptr&
}


StaticArray#(.t, .n) : Type = [
    ---
    A heap allocated static array
    ---
    ._data      : HeapAllocation
    ._data_type : Type        = t
    ._length    : Int         = n
    ._alignment : Alignment   = ..Default
]

StaticList#(.t, .n) canbe StaticArray#(.t, .n)

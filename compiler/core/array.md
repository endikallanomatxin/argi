Array#(.t: Type, .n: Int) : Type = (
    -- This is a stack allocated array.
    -- Similar to the default array in C or zig, when not using malloc.
    ._data      : &Byte
    ._data_type : t
    ._length    : UInt64    = n  -- Igual 64 es demasiado?
    -- ._alignment : Alignment   = ..Default
)

my_array : Array#(Int, 3) = (1, 2, 3)

init (
    .a: Array#(.t, .n),  -- En init, qué pasa con las generics?
    .lit: ArrayLiteral
) -> (
    .a: Array#(.t, .n)
) := {
    n := length(lit)
    t := typeOf(lit[0])

    size := size_of(.type=t) * n
    alignment := alignment_of(.type=t)
    a._data = alloca(size, alignment)
    a._data_type = t
    a._length = n
}

operator get[] (
    .pointer_to_a: &StackArray#(.t, .n),
    .i:Int
) -> (
    .v: t
) := {
    -- if i < 1 or i > N {
    --     panic("Index out of bounds")
    -- }

    -- Read from i to i + sizeof(T)
    offset := [i - 1] * sizeOf(.type=t)
    ptr : &t = a + offset
    v = *ptr
}



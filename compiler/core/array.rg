-- Minimal array abstraction; functionality will be expanded in the future.
Array#(.t: Type) : Type = (
    -- TODO: Make length a compile-time parameter
    .data: $&Any,
    .length: UInt64 = 0,
    -- ._data_type : t
    -- ._alignment : Alignment   = ..Default
)

init (.a: $&Array#(.t), .lit: Int32) -> () := {
    -- TODO: Take an array literal

    puts(.string="Array init called")

    -- TODO: Implement

    -- n := length(lit)
    -- t := typeOf(lit[0])

    -- size := size_of(.type=t) * n
    -- alignment := alignment_of(.type=t)
    -- a._data = alloca(size, alignment)
    -- a._data_type = t
    -- a._length = n
}

deinit (.a: $&Array#(.t)) -> () := {
    -- if (a._data != null) {
    --     free(a._data)
    --     a._data = null
    --     a._length = 0
    -- }
}

operator get[](.self: &Array#(.t), .i: Int32) -> (.v: Int32) := {
    puts(.string="get[] called")

    -- TODO: Implement

    -- if i < 1 or i > N {
    --     panic("Index out of bounds")
    -- }

    -- Read from i to i + sizeof(T)
    -- offset := [i - 1] * sizeOf(.type=t)
    -- ptr : &t = a + offset
    -- v = *ptr
}

operator set[](.self: $&Array#(.t), .i: Int32, .value: Int32) -> () := {
    puts(.string="set[] called")

    -- TODO: Implement
}

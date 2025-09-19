-- Minimal index operator demo using a named type and a function
Pair : Type = (
    .x: Int32,
    .y: Int32,
)

-- Define the index get operator as a normal function
-- Convention: op_index_get(.self: T, .i: Int32) -> (.v: T)
operator get[](.self: &Pair, .i: Int32) -> (.v: Int32) := {
    temp :: Pair = self&
    if i == 1 {
        v = temp.x
    } else {
        v = temp.y
    }
}

operator set[](.self: $&Pair, .i: Int32, .value: Int32) -> () := {
    temp :: Pair = self&

    if i == 1 {
        temp = (.x=value, .y=temp.y)
    } else {
        temp = (.x=temp.x, .y=value)
    }

    self& = temp
}

main () -> (.status_code: Int32) := {
    p :: Pair = (.x=10, .y=20)
    initial :: Int32 = p[2]

    if initial != 20 {
        status_code = 1
        return
    }

    -- From the variable itself
    p[1] = 42

    -- From a read-write pointer
    ptr := $&p
    ptr[2] = 73

    first_after :: Int32 = p[1]
    if first_after != 42 {
        status_code = 2
        return
    }

    second_after :: Int32 = p[2]
    if second_after != 73 {
        status_code = 3
        return
    }

    status_code = 0
}

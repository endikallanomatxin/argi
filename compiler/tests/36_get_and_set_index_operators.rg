-- Minimal index operator demo using a named type and a function

Pair : Type = (
    .x: Int32,
    .y: Int32,
)

-- Define the index get operator as a normal function
-- Convention: op_index_get(.self: T, .i: Int32) -> (.v: T)
operator get[](.self: Pair, .i: Int32) -> (.v: Int32) := {
    if i == 1 {
        v = self.x
    } else {
        v = self.y
    }
}

main () -> (.status_code: Int32) := {
    p : Pair = (.x=10, .y=20)
    s : Int32 = p[2]
    status_code = 0
}


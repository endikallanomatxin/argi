is_origin(.self: Point) -> (.ok: Bool) := {
    ok = self.x == 0 and self.y == 0
}

uses_sum(.self: Point) -> (.ok: Bool) := {
    if sum(.self = self).value == 42 {
        ok = true
        return
    }

    ok = false
}

sum(.self: Point) -> (.value: Int32) := {
    value = self.x + self.y
}

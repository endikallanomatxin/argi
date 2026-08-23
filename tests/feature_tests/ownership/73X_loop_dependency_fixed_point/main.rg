Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

deinit(.self: $$&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    one :: Resource = (.value = 1)
    two :: Resource = (.value = 2)
    three :: Resource = (.value = 3)
    victim :: Resource = (.value = 4)
    first :: Holder = (.pointer = &one)
    second :: Holder = (.pointer = &two)
    third :: Holder = (.pointer = &three)
    running :: Bool = true

    while running {
        first.pointer = second.pointer
        second.pointer = third.pointer
        third.pointer = &victim
        running = false
    }

    deinit(.self = $$&victim)
    read(.value = first.pointer)
    status_code = 0
}

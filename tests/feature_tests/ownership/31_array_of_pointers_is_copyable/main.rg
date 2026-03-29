Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

consume_ptr(.ptr: &Resource) -> (.status_code: Int32) := {
    status_code = 0
}

main() -> (.status_code: Int32) := {
    first := Resource()
    second := Resource()

    pointers :: [2]&Resource = (&first, &second)
    copied : [2]&Resource = pointers

    if consume_ptr(.ptr = copied[0]).status_code != 0 {
        status_code = 1
        return
    }

    if consume_ptr(.ptr = copied[1]).status_code != 0 {
        status_code = 2
        return
    }

    status_code = 0
}

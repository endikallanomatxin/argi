increment_in_place (.value: $&Int32) -> (.done: Int32) := {
    value& = value& + 1
    done = 1
}

read_value (.value: &Int32) -> (.r: Int32) := {
    r = value&
}

main () -> (.status_code: Int32) := {
    value :: Int32 = 41
    done : Int32 = value | increment_in_place(.value = $&_)

    if done != 1 {
        status_code = 1
        return
    }

    status_code = value | read_value(.value = &_)
}

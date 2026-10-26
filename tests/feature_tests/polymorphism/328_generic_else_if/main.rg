ordinary := (.value: Int32) -> (.result: Int32) {
    if value < 0 { result = -1 } else if value == 0 { result = 0 } else { result = 1 }
}

classify := <.T: Type> (.value: T) -> (.result: Int32) {
    if value < 0 {
        result = -1
    } else if value == 0 {
        result = 0
    } else if value < 10 {
        result = 1
    } else {
        result = 2
    }
}

main := () -> () {
    if ordinary(-1).result != -1 or ordinary(0).result != 0 or ordinary(1).result != 1 {
        abort
    }
    if classify<Int32>(-2).result != -1 { abort }
    if classify<Int32>(0).result != 0 { abort }
    if classify<Int32>(3).result != 1 { abort }
    if classify<Int64>(20).result != 2 { abort }
}

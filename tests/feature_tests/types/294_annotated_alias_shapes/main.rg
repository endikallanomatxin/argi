base ::= import ("./base")

Record: Type = base.Record

Pair: Type = [2]UIntNative

Option: Type = (..empty, ..some Int32)

Choice: Type = Option

GenericId: Type = <.Base: Type> Base

main := () -> (.status_code: Int32 = 0) {
    record: Record = (.value = 42)
    if record.value != 42 { status_code = 1 }
    pair: Pair = (3, 4)
    if pair[0] != 3 or pair[1] != 4 { status_code = 2 }
    choice: Choice = ..some 7
    if choice == ..some {
        value := choice ..some
        if value != 7 { status_code = 4 }
    } else {
        status_code = 3
    }
    id: GenericId<UIntNative> = 12
    if id + 1 != 13 { status_code = 5 }
}

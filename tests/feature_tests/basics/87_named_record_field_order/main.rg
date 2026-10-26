Pair := (.number: UIntNative, .flag: Bool)

Record := (.number: UIntNative, .flag: Bool, .tail: Int32)

Box := <.T: Type> (.value: T, .present: Bool)

Borrow := (.first: &Int32, .second: &Int32)

read := (.input: Record) -> (.ok: Bool) {
    ok = input.number == 7 and input.flag and input.tail == -9
}

make := <.T: Type> (.value: T) -> (.result: Box<T>) {
    result = (.present = true, .value = value)
}

main := () -> (.status_code: Int32 = 0) {
    pair: Pair = (.flag = true, .number = 7)
    if pair.number != 7 or pair.flag == false { status_code = 1 }
    record :: Record = (.tail = -9, .flag = true, .number = 7)
    if read(.input = record).ok == false { status_code = 2 }
    record = (.flag = true, .number = 7, .tail = -9)
    if read(.input = record).ok == false { status_code = 3 }
    boxed ::= make(.value = record)
    if boxed.present == false or read(.input = boxed.value).ok == false { status_code = 4 }
    a: Int32 = 17
    b: Int32 = 29
    refs: Borrow = (.second = &b, .first = &a)
    if refs.first&!= 17 or refs.second&!= 29 { status_code = 5 }
    values: [2]Pair = ((.flag = false, .number = 3), (.number = 8, .flag = true))
    if values[0].number != 3 or values[0].flag { status_code = 6 }
    if values[1].number != 8 or values[1].flag == false { status_code = 7 }
    if keep(.stable = &a)&!= 17 { status_code = 8 }
}

keep := (.stable: &Int32) -> (.result: &Int32) {
    local: Int32 = 41
    refs: Borrow = (.second = &local, .first = stable)
    result = refs.first
}

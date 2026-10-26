Mode: CEnum = (..first, ..second)

Callback(.value: CInt) -> (.result: CInt): CFunctionPointer

same := <.T: Type> (.a: T, .b: T) -> (.ok: Bool) { ok = a == b }

main := () -> (.status_code: Int32 = 0) {
    a: Mode = ..first
    b: Mode = ..second
    if a == b or [a != b] == false or same(a, a).ok == false { status_code = 1 }
    if [
        Equal<Mode, Mode, (.left: Mode, .right: Mode)>.equal(.args = (.left = a, .right = a)).ok
        == false
    ] { status_code = 2 }
    callback ::= zeroed<.t: Callback>()
    if same(callback, callback).ok == false or callback != callback { status_code = 3 }
    if [
        Equal<Callback, Callback, (.left: Callback, .right: Callback)>.equal(
            .args = (.left = callback, .right = callback)
        ).ok
        == false
    ] { status_code = 4 }
}

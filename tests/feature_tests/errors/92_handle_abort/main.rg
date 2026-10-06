..missing

attempt() -> (.result: Errable#(Void, (..missing))) := {
    result = ..error(.reason = ..missing)
}

main() -> (.status_code: Int32 = 0) := { attempt() handle error { abort } }

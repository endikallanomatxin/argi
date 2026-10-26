fail := () -> !Void = ..ok Void() {}

main := () -> (.status_code: Int32 = 0) { defer { fail()!!! { status_code = 1 } } }

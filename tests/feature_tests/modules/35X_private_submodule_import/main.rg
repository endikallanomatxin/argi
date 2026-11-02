hidden := import("./tree/_detail")
main := () -> (.status_code: Int32 = 0) { return hidden.answer() }

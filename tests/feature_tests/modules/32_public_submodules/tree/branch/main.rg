internal := import("../_detail")
private_answer := () -> (.value: Int32) { value = internal.answer() }

root := import("./tree")
main := () -> (.status_code: Int32 = 0) {
    return root._detail.answer()
}

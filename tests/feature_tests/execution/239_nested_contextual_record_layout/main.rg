main := () -> (.status_code: Int32) {
    value: (.left: Int32, .inner: (.first: Int32, .second: Int32), .right: Int32) = (
        .right = 1
        .inner = (.second = 20, .first = 21)
        .left  = 0
    )
    status_code = value.inner.first + value.inner.second + value.right
}

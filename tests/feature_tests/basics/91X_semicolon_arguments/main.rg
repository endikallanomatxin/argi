add := (.left: Int32, .right: Int32) -> (.value: Int32) { return left + right; }
main := () -> (.status_code: Int32 = 0) {
    return add(1; 2);
}

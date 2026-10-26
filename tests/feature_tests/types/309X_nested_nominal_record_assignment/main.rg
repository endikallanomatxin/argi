First := (.value: Bool)
Second := (.value: Bool)
Container := (.item: First)

main := () -> () {
    other: Second = (.value = true)
    container: Container = (.item = other)
}

Context := (._counter: $&Int32)
make := (.value: $&Int32) -> (.context: Context) { context = (._counter = value) }

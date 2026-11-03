Secret := (._hidden: Int32)
make := () -> (.result: Secret) { result = (._hidden = 42) }

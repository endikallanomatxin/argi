Foreign := (.value: Int32)

Box := <.T: Type> (.value: T)

Inspect<.Value: Type>: Contract = (
    .inspect : (.value: Value) -> (.result: Int32)
)

Readable<.T: Type>: Contract = (.read: (.source: T) -> (.result: Int32))

Box := <.T: Type> (.value: T)

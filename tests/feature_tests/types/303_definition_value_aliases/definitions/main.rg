Box := #(.T: Type) (.value: T)

ExportedBox := Box

identity := #(.T: Type) (.value: T) -> (.result: T) {
    result = value
}

ExportedIdentity := identity

Marker := (.value: Int32)

measure := #(.T: Type) (.value: T) -> (.result: UIntNative) {
    _ = identity#(T)(.value = value)
    result = size_of(.type = Marker)
}

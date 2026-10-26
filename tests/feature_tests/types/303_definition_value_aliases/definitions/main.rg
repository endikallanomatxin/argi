Box := <.T: Type> (.value: T)

ExportedBox := Box

identity := <.T: Type> (.value: T) -> (.result: T) {
    result = value
}

ExportedIdentity := identity

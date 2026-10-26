dep := import ("../dep")

consume_imported := <.Value: Type: dep.Capability> (.value: Value) -> (.result: Int32) {
    result = dep.score(.value = value).result
}

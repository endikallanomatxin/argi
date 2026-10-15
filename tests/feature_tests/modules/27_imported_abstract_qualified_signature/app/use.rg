dep := import("../dep")

consume_imported#(.Value: Type: dep.Abstract) := (.value: Value) -> (.result: Int32) {
    result = dep.score(.value = value).result
}

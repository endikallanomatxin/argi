add(.left: Int32, .right: Int32) -> (.value: Int32) := { value = left + right }
identity#(.t: Type)(.value: t) -> (.result: t) := { result = value }

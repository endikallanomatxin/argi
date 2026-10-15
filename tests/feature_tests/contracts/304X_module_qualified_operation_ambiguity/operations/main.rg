First#(.Value: Type): Contract = (.query: (.value: Value) -> (.result: Int32))
Second#(.Value: Type): Contract = (.query: (.value: Value) -> (.result: Int32))
implement First#(Int32) (.query = (.value: Int32) -> (.result: Int32) { result = value })
implement Second#(Int32) (.query = (.value: Int32) -> (.result: Int32) { result = value })

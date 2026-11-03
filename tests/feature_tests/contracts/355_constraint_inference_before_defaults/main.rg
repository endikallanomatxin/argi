Source#(.T: Type): Contract = (.Item: Type)
Flag: Type = ()
implement Source#(Flag) (.Item: Type = Bool)
identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

read := #(.T: Type: Source#(.Item: Item), .Item: Type = Int32, .F: Function = identity#(Item)) (.source: T) -> (.result: Item) {
    _ = source
    result = F(.value = true)
}

Runner#(.T: Type): Contract = (.Chosen: Function, .run: _)
implement#(.T: Type: Source#(.Item: Item), .Item: Type = Int32, .F: Function = identity#(Item)) Runner#(T) (
    .Chosen: Function = F
    .run = identity#(Item)
)

main := () -> () {
    if read(.source = Flag()) {} else { abort }
    if Runner#(Flag).run(true) {} else { abort }
    value: result_of#(Runner#(Flag).Chosen) = true
    if value {} else { abort }
}

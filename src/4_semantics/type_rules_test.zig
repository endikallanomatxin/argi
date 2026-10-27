const checkSyntaxSource = @import("source_test_support.zig").checkSyntaxSource;
const checkSource = @import("source_test_support.zig").checkSource;

test "type rules: 314X_generic_operation_result_mismatch" {
    try checkSource(
        "314X_generic_operation_result_mismatch",
        \\Identity#(.Owner: Type): Contract = (
        \\    .apply : #(.Value: Type) (.value: Value) -> (.result: Value)
        \\)
        \\
        \\Owner := (.flag: Bool)
        \\
        \\wrong := #(.Item: Type) (.value: Item) -> (.result: Int32) { result = 42 }
        \\
        \\implement Identity#(Owner) (.apply = wrong)
        \\
        \\main := () -> () {
        \\    result: Bool = Identity#(Owner).apply(.value = true).result
        \\}
    ,
        null,
        "operation returns an incompatible associated result",
        false,
    );
}

test "type rules: 315X_virtual_generic_contract_operation" {
    try checkSource(
        "315X_virtual_generic_contract_operation",
        \\Readable#(.Participant: Type): Contract = (
        \\    .read : #(.Value: Type) (.owner: &Participant, .value: Value) -> (.result: Value)
        \\)
        \\
        \\Owner := (.flag: Bool)
        \\
        \\implement Readable#(Owner) (
        \\    .read = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Item) { result = value }
        \\)
        \\
        \\main := () -> () {
        \\    owner: Owner = (.flag = true)
        \\    handle ::= to_virtual#(.contract: Readable)(.value = &owner)
        \\}
    ,
        null,
        "generic contract operations require static specialization and cannot be virtualized",
        false,
    );
}

test "type rules: 317X_generic_operation_identity_ambiguity" {
    try checkSource(
        "317X_generic_operation_identity_ambiguity",
        \\Allowed#(.Value: Type): Contract = ()
        \\
        \\implement Allowed#(Bool) ()
        \\
        \\Constrained#(.Participant: Type): Contract = (
        \\    .route : #(.Value: Type: Allowed#(Value)) (.owner: &Participant, .value: Value) -> (
        \\        .result : Bool
        \\    )
        \\)
        \\
        \\Open#(.Participant: Type): Contract = (
        \\    .route : #(.Value: Type) (.owner: &Participant, .value: Value) -> (.result: Bool)
        \\)
        \\
        \\Owner := (.flag: Bool)
        \\
        \\implement Constrained#(Owner) (
        \\    .route = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Bool) { result = true }
        \\)
        \\
        \\implement Open#(Owner) (
        \\    .route = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Bool) { result = false }
        \\)
        \\
        \\main := () -> () {
        \\    owner: Owner = (.flag = true)
        \\    if route(.owner = &owner, .value = true).result { abort }
        \\}
    ,
        null,
        "multiple applicable operation identities",
        false,
    );
}

test "type rules: 318X_unknown_operation_parameter" {
    try checkSource(
        "318X_unknown_operation_parameter",
        \\Identity#(.Owner: Type): Contract = (
        \\    .apply : #(.Value: Type) (.value: Value) -> (.result: Value)
        \\)
        \\
        \\Owner := (.flag: Bool)
        \\
        \\implement Identity#(Owner) (
        \\    .apply = #(.Item: Type) (.value: Item) -> (.result: Item) { result = value }
        \\)
        \\
        \\main := () -> () {
        \\    result: Bool = Identity#(Owner).apply#(.Missing: Bool)(.value = true).result
        \\}
    ,
        null,
        "unknown compile-time argument",
        false,
    );
}

test "type rules: 319X_excess_operation_parameters" {
    try checkSource(
        "319X_excess_operation_parameters",
        \\Identity#(.Owner: Type): Contract = (
        \\    .apply : #(.Value: Type) (.value: Value) -> (.result: Value)
        \\)
        \\
        \\Owner := (.flag: Bool)
        \\
        \\implement Identity#(Owner) (
        \\    .apply = #(.Item: Type) (.value: Item) -> (.result: Item) { result = value }
        \\)
        \\
        \\main := () -> () {
        \\    result: Bool = Identity#(Owner).apply#(Bool, Int32)(.value = true).result
        \\}
    ,
        null,
        "too many compile-time arguments",
        false,
    );
}

test "type rules: 322X_generic_operation_conflicting_inputs" {
    try checkSource(
        "322X_generic_operation_conflicting_inputs",
        \\Pair#(.Owner: Type): Contract = (
        \\    .pair : #(.Value: Type) (.left: Value, .right: Value) -> (.result: Bool)
        \\)
        \\
        \\Owner := (.unused: Bool)
        \\
        \\implement Pair#(Owner) (
        \\    .pair = #(.Item: Type) (.left: Item, .right: Item) -> (.result: Bool) { result = true }
        \\)
        \\
        \\main := () -> () {
        \\    value: Bool = Pair#(Owner).pair(.left = true, .right = 42).result
        \\}
    ,
        null,
        "conflicting inferred generic parameters in call to 'pair'",
        false,
    );
}

test "type rules: 327X_associated_family_signature" {
    try checkSource(
        "327X_associated_family_signature",
        \\Owner := (.flag: Bool)
        \\
        \\Arguments := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\Factory#(.Participant: Type): Contract = (
        \\    .Args : #(.Item: Type) Type
        \\)
        \\
        \\implement Factory#(Owner) (
        \\    .Args : #(.Item: Type) Type = Arguments
        \\)
        \\
        \\main := () -> () {}
    ,
        null,
        "associated type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 328X_associated_type_as_family" {
    try checkSource(
        "328X_associated_type_as_family",
        \\Owner := (.flag: Bool)
        \\
        \\Arguments := (.value: Bool)
        \\
        \\Factory#(.Participant: Type): Contract = (
        \\    .Args : Type
        \\)
        \\
        \\implement Factory#(Owner) (
        \\    .Args : Type = Arguments
        \\)
        \\
        \\main := () -> () {
        \\    value: Factory#(Owner).Args#(Bool) = (.value = true)
        \\}
    ,
        null,
        "associated element is not a type family",
        false,
    );
}

test "type rules: 330X_explicit_operation_identity" {
    try checkSource(
        "330X_explicit_operation_identity",
        \\Owner := (.flag: Bool)
        \\
        \\First#(.Participant: Type): Contract = (
        \\    .choose : #(.Item: Type) (.owner: &Participant, .value: Item) -> (.result: Bool)
        \\)
        \\
        \\Second#(.Participant: Type): Contract = (
        \\    .choose : #(.Item: Type) (.owner: &Participant, .value: Item) -> (.result: Bool)
        \\)
        \\
        \\implement First#(Owner) (
        \\    .choose = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Bool) {
        \\        result = owner&.flag
        \\    }
        \\)
        \\
        \\implement Second#(Owner) (
        \\    .choose = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Bool) {
        \\        result = owner&.flag
        \\    }
        \\)
        \\
        \\main := () -> () {
        \\    owner: Owner = (.flag = true)
        \\    if choose#(Bool)(.owner = &owner, .value = true).result {} else { abort }
        \\}
    ,
        null,
        "multiple applicable operation identities",
        false,
    );
}

test "type rules: 331X_nested_family_signature" {
    try checkSource(
        "331X_nested_family_signature",
        \\Outer := #(.Nested: #(.Left: Type, .Right: Type) Type) (.flag: Bool)
        \\
        \\accept := #(.Family: #(.Nested: #(.Item: Type) Type) Type) () -> () {}
        \\
        \\main := () -> () {
        \\    accept#(.Family = Outer)()
        \\}
    ,
        null,
        "type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 335X_family_integer_parameter_type" {
    try checkSource(
        "335X_family_integer_parameter_type",
        \\Narrow := #(.count: UInt8) (.flag: Bool)
        \\
        \\accept := #(.Family: #(.count: UIntNative) Type) () -> () {}
        \\
        \\main := () -> () {
        \\    accept#(.Family = Narrow)()
        \\}
    ,
        null,
        "type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 337X_nested_family_integer_parameter_type" {
    try checkSource(
        "337X_nested_family_integer_parameter_type",
        \\Narrow := #(.Family: #(.count: UInt8) Type) (.flag: Bool)
        \\
        \\accept := #(.Outer: #(.Family: #(.count: UIntNative) Type) Type) () -> () {}
        \\
        \\main := () -> () {
        \\    accept#(.Outer = Narrow)()
        \\}
    ,
        null,
        "type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 339X_runtime_array_dimension" {
    try checkSource(
        "339X_runtime_array_dimension",
        \\count :: UIntNative = 2
        \\
        \\main := () -> () {
        \\    values: [count]Int32 = (20, 22)
        \\}
    ,
        null,
        "runtime values cannot be used",
        false,
    );
}

test "type rules: 343X_family_incompatible_bound" {
    try checkSource(
        "343X_family_incompatible_bound",
        \\First#(.Value: Type): Contract = ()
        \\
        \\Second#(.Value: Type): Contract = ()
        \\
        \\Restricted := #(.Item: Type: Second#(Item)) (.value: Item)
        \\
        \\accept := #(.Family: #(.T: Type: First#(T)) Type) () -> () {}
        \\
        \\main := () -> () { accept#(.Family = Restricted)() }
    ,
        null,
        "type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 345X_family_bound_arguments" {
    try checkSource(
        "345X_family_bound_arguments",
        \\Related#(.Left: Type, .Right: Type): Contract = ()
        \\
        \\Restricted := #(.Item: Type: Related#(Item, Bool)) (.value: Item)
        \\
        \\accept := #(.Family: #(.T: Type: Related#(T, Int32)) Type) () -> () {}
        \\
        \\main := () -> () { accept#(.Family = Restricted)() }
    ,
        null,
        "type-family argument does not match its parameter signature",
        false,
    );
}

test "type rules: 347X_generic_record_missing_context" {
    try checkSource(
        "347X_generic_record_missing_context",
        \\make := #(.T: Type) (.value: T) -> () {
        \\    record ::= (.value = value)
        \\}
        \\
        \\main := () -> () { make(42) }
    ,
        null,
        "add an explicit type annotation",
        false,
    );
}

test "type rules: 355X_generic_scalar_input_signature" {
    try checkSource(
        "355X_generic_scalar_input_signature",
        \\accept_record := #(.Args: Type) Args -> () {}
        \\
        \\main := () -> () {
        \\    selected := accept_record#(Int32)
        \\    selected(42)
        \\}
    ,
        null,
        "arguments do not match this specialized function definition",
        false,
    );
}

test "type rules: 356X_generic_scalar_output_signature" {
    try checkSource(
        "356X_generic_scalar_output_signature",
        \\produce := #(.Result: Type) () -> Result {}
        \\
        \\main := () -> () { produce#(Int32)() }
    ,
        null,
        "function output signature must be a record type",
        false,
    );
}

test "type rules: types/290X_nominal_record_mismatch" {
    try checkSource(
        "types/290X_nominal_record_mismatch",
        \\VertexId := (.value: UIntNative)
        \\
        \\EdgeId := (.value: UIntNative)
        \\
        \\accept := (.value: VertexId) -> () {}
        \\
        \\main := () -> () {
        \\    edge: EdgeId = (.value = 1)
        \\    accept(.value = edge)
        \\}
    ,
        null,
        "no function named 'accept' accepts arguments (.value: EdgeId)",
        false,
    );
}

test "type rules: types/292X_annotated_alias_range" {
    try checkSource(
        "types/292X_annotated_alias_range",
        \\SmallId: Type = UInt8
        \\
        \\main := () -> () {
        \\    value: SmallId = 256
        \\}
    ,
        null,
        "integer literal 256 does not fit in 'UInt8'",
        false,
    );
}

test "type rules: types/293X_type_alias_cycle" {
    try checkSource(
        "types/293X_type_alias_cycle",
        \\First: Type = Second
        \\
        \\Second: Type = First
        \\
        \\main := () -> () {}
    ,
        null,
        "cyclic type alias",
        false,
    );
}

test "type rules: types/295X_independent_record_contract" {
    try checkSource(
        "types/295X_independent_record_contract",
        \\Marked#(.T: Type): Contract = ()
        \\
        \\Base := (.value: Int32)
        \\
        \\Derived := (.value: Int32)
        \\
        \\implement Marked#(Base) ()
        \\
        \\require_mark := #(.T: Type: Marked) (.value: T) -> () {}
        \\
        \\main := () -> () {
        \\    value: Derived = (.value = 1)
        \\    require_mark(.value = value)
        \\}
    ,
        null,
        "does not satisfy contract constraint 'Marked'",
        false,
    );
}

test "type rules: types/297X_nominal_record_raw_argument" {
    try checkSource(
        "types/297X_nominal_record_raw_argument",
        \\VertexId := (.value: UIntNative)
        \\
        \\accept_raw := (.value: UIntNative) -> () {}
        \\
        \\main := () -> () {
        \\    vertex: VertexId = (.value = 1)
        \\    accept_raw(.value = vertex)
        \\}
    ,
        null,
        "no function named 'accept_raw' accepts arguments (.value: VertexId)",
        false,
    );
}

test "type rules: types/305X_named_signature_conflicting_types" {
    try checkSource(
        "types/305X_named_signature_conflicting_types",
        \\Args := #(.T: Type) (.left: T, .right: T)
        \\
        \\Result := #(.T: Type) (.result: T)
        \\
        \\choose := #(.T: Type) Args#(T) -> Result#(T) {
        \\    result = left
        \\}
        \\
        \\main := () -> () {
        \\    left: Int32 = 1
        \\    right: Int64 = 2
        \\    _ = choose(.left = left, .right = right)
        \\}
    ,
        null,
        "conflicting inferred generic parameters",
        false,
    );
}

test "type rules: types/310X_array_nominal_record_assignment" {
    try checkSource(
        "types/310X_array_nominal_record_assignment",
        \\First := (.value: Bool)
        \\Second := (.value: Bool)
        \\
        \\main := () -> () {
        \\    other: Second = (.value = true)
        \\    items: [1]First = (other,)
        \\}
    ,
        null,
        "distinct nominal types require explicit conversion",
        false,
    );
}

test "type rules: types/329X_associated_family_capture_identity" {
    try checkSource(
        "types/329X_associated_family_capture_identity",
        \\First := (.flag: Bool)
        \\
        \\Second := (.flag: Bool)
        \\
        \\Factory#(.Participant: Type): Contract = (
        \\    .Args : #(.Item: Type) Type
        \\)
        \\
        \\implement#(.Participant: Type) Factory#(Participant) (
        \\    .Args : #(.Item: Type) Type = #(.Item: Type) (.value: Item)
        \\)
        \\
        \\main := () -> () {
        \\    first: Factory#(First).Args#(Bool) = (.value = true)
        \\    second: Factory#(Second).Args#(Bool) = first
        \\}
    ,
        null,
        "distinct nominal types require explicit conversion",
        false,
    );
}

test "type rules: types/72X_virtual_inference_missing_context" {
    try checkSource(
        "types/72X_virtual_inference_missing_context",
        \\Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})
        \\
        \\Other#(.Participant: Type): Contract = ()
        \\
        \\Probe := (.value: UIntNative = 0)
        \\
        \\implement Counter#(Probe) (.bump = _impl_bump_Probe)
        \\
        \\implement Other#(Probe) ()
        \\
        \\_impl_bump_Probe := (.self: $&Probe) -> () { self&.value = self&.value + 1 }
        \\
        \\main := () -> (.status_code: Int32) {
        \\    probe ::= Probe()
        \\    handle ::= to_virtual($&probe)
        \\    status_code = 0
        \\}
    ,
        null,
        "cannot infer the contract parameter",
        false,
    );
}

test "type rules: polymorphism/02X_multiple_dispatch_ambiguous" {
    try checkSource(
        "polymorphism/02X_multiple_dispatch_ambiguous",
        \\Selection#(.Left: Type, .Right: Type): Contract = (
        \\    .choose2 : (.a: &Left, .b: &Right) -> (.r: Int32)
        \\)
        \\
        \\implement#(.Left: Type) Selection#(Left, Int32) (
        \\    .choose2 = (.a: &Left, .b: &Int32) -> (.r: Int32) { r = 10 }
        \\)
        \\
        \\implement#(.Right: Type) Selection#(Int32, Right) (
        \\    .choose2 = (.a: &Int32, .b: &Right) -> (.r: Int32) { r = 20 }
        \\)
        \\
        \\main := () -> (.status_code: Int32) {
        \\    i: Int32 = 5
        \\    status_code = choose2(.a = &i, .b = &i).r
        \\}
    ,
        null,
        "ambiguous maximal patterns",
        false,
    );
}

test "type rules: polymorphism/09X_abstract_missing_requirement" {
    try checkSource(
        "polymorphism/09X_abstract_missing_requirement",
        \\Dog := (
        \\    .name : Int32 = 0
        \\)
        \\
        \\Animal#(.Participant: Type): Contract = (
        \\    .speak : (.who: Participant) -> (.s: &CChar)
        \\)
        \\
        \\implement Animal#(Dog) ()
        \\
        \\main := () -> (.status_code: Int32) {
        \\    status_code = 0
        \\}
    ,
        null,
        "missing implementation operation",
        false,
    );
}

test "type rules: polymorphism/103X_static_safety_contract_readonly" {
    try checkSource(
        "polymorphism/103X_static_safety_contract_readonly",
        \\Editor#(.Participant: Type): Contract = (
        \\    .edit : (.self: &Participant, .target: &Int32) -> () where invalidates(target)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Editor#(Cell) (.edit = _impl_edit_Cell)
        \\
        \\_impl_edit_Cell := (.self: &Cell, .target: &Int32) -> () {}
        \\
        \\main := () -> () {}
    ,
        null,
        "invalidates requires a mutable reference input",
        false,
    );
}

test "type rules: polymorphism/104X_static_safety_contract_reference_transfer" {
    try checkSource(
        "polymorphism/104X_static_safety_contract_reference_transfer",
        \\Mover#(.Participant: Type): Contract = (
        \\    .move : (.self: &Participant, .input: &Int32) -> (.value: &Int32) where transfers(
        \\        value, input
        \\    )
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Mover#(Cell) (.move = _impl_move_Cell)
        \\
        \\_impl_move_Cell := (.self: &Cell, .input: &Int32) -> (.value: &Int32) {
        \\    value = ~input
        \\}
        \\
        \\main := () -> () {}
    ,
        null,
        "transfers requires a by-value owning input",
        false,
    );
}

test "type rules: polymorphism/106X_virtual_safety_contract_domain_result_unknown" {
    try checkSource(
        "polymorphism/106X_virtual_safety_contract_domain_result_unknown",
        \\Source#(.Participant: Type): Contract = (
        \\    domain storage
        \\    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
        \\    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell, .reset = _impl_reset_Cell) where {
        \\    storage(self.value)
        \\}
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) { value = &self&.value }
        \\
        \\_impl_reset_Cell := (.self: $&Cell) -> () { self&.value = 42 }
        \\
        \\Relay#(.Participant: Type): Contract = (
        \\    .forward : (.self: &Participant, .source: Virtual#(Source)) -> (.value: Virtual#(Source))
        \\    where depends_on(value, source)
        \\)
        \\
        \\RelayCell := (.unused: Int32)
        \\
        \\implement Relay#(RelayCell) (.forward = _impl_forward_RelayCell)
        \\
        \\_impl_forward_RelayCell := (.self: &RelayCell, .source: Virtual#(Source)) -> (
        \\    .value : Virtual#(Source)
        \\) {
        \\    value = ~source
        \\}
        \\
        \\forward_again := (.relay: &Virtual#(Relay), .source: Virtual#(Source)) -> (
        \\    .value : Virtual#(Source)
        \\) {
        \\    value = forward(relay, ~source)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    cell ::= Cell(41)
        \\    relay_cell ::= RelayCell(0)
        \\    relay ::= to_virtual#(Relay)(&relay_cell)
        \\    source ::= to_virtual#(Source)($&cell)
        \\    forwarded ::= forward_again(&relay, ~source)
        \\    old ::= get(&forwarded)
        \\    if old&!= 41 { status_code = 1 }
        \\    reset($&forwarded)
        \\    current ::= get(&forwarded)
        \\    if current&!= 42 { status_code = 1 }
        \\
        \\}
    ,
        null,
        "preserve its domain identities",
        false,
    );
}

test "type rules: polymorphism/10X_abstract_wrong_signature" {
    try checkSource(
        "polymorphism/10X_abstract_wrong_signature",
        \\Dog := (
        \\    .name : Int32 = 0
        \\)
        \\
        \\Animal#(.Participant: Type): Contract = (
        \\    .speak : (.who: Participant) -> (.s: &CChar)
        \\)
        \\
        \\implement Animal#(Dog) (.speak = _impl_speak_Dog)
        \\
        \\-- Wrong function signature: expects a &CChar return type, but it's an Int32
        \\_impl_speak_Dog := (.who: Dog) -> (.s: Int32) {
        \\    s = 42
        \\}
        \\
        \\main := () -> (.status_code: Int32) {
        \\    status_code = 0
        \\}
    ,
        null,
        "incompatible associated result",
        false,
    );
}

test "type rules: polymorphism/110X_virtual_safety_contract_missing" {
    try checkSource(
        "polymorphism/110X_virtual_safety_contract_missing",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.value: Int32)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell)
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.value: Int32) { value = self&.value }
        \\
        \\main := () -> () {
        \\    cell ::= Cell(42)
        \\    source ::= to_virtual#(Source)(&cell)
        \\}
    ,
        null,
        "virtual methods require a declared safety contract",
        false,
    );
}

test "type rules: polymorphism/112X_virtual_safety_contract_unknown_selector" {
    try checkSource(
        "polymorphism/112X_virtual_safety_contract_unknown_selector",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.result: ?Int32) where {
        \\        on missing ..some {}
        \\    }
        \\)
        \\
        \\main := () -> () {}
    ,
        null,
        "on must select a named method input or output",
        false,
    );
}

test "type rules: polymorphism/113X_virtual_safety_contract_scalar_selector" {
    try checkSource(
        "polymorphism/113X_virtual_safety_contract_scalar_selector",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.count: Int32, .result: ?Int32) where {
        \\        on count ..some {}
        \\    }
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell)
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.count: Int32, .result: ?Int32) {
        \\    count = 0
        \\    result = ..none
        \\}
        \\
        \\main := () -> () {}
    ,
        null,
        "on requires a choice-valued output",
        false,
    );
}

test "type rules: polymorphism/114X_virtual_safety_contract_duplicate_selector" {
    try checkSource(
        "polymorphism/114X_virtual_safety_contract_duplicate_selector",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.first: ?Int32, .second: ?Int32) where {
        \\        on first ..some {}
        \\        on second ..some {}
        \\        on second ..some {}
        \\    }
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell)
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.first: ?Int32, .second: ?Int32) {
        \\    first = ..none
        \\    second = ..none
        \\}
        \\
        \\main := () -> () {}
    ,
        null,
        "duplicate outcome contract",
        false,
    );
}

test "type rules: polymorphism/12X_abstract_instantiation_missing_default" {
    try checkSource(
        "polymorphism/12X_abstract_instantiation_missing_default",
        \\ExampleAbstract#(.Participant: Type): Contract = ()
        \\
        \\main := () -> (.status_code: Int32) {
        \\    x: ExampleAbstract
        \\    status_code = 0
        \\}
    ,
        null,
        "contract 'ExampleAbstract' has no runtime representation",
        false,
    );
}

test "type rules: polymorphism/13X_abstract_function_input_requires_implementation" {
    try checkSource(
        "polymorphism/13X_abstract_function_input_requires_implementation",
        \\ExampleAbstract#(.Participant: Type): Contract = ()
        \\
        \\use_value := #(.Value: Type: ExampleAbstract) (.value: Value) -> (.status_code: Int32) {
        \\    status_code = 1
        \\}
        \\
        \\main := () -> (.status_code: Int32) {
        \\    status_code = use_value(.value = 7)
        \\}
    ,
        null,
        "contract constraint 'ExampleAbstract' required by generic function parameter '.Value' of 'use_value'",
        false,
    );
}

test "type rules: polymorphism/14X_abstract_function_output_requires_default" {
    try checkSource(
        "polymorphism/14X_abstract_function_output_requires_default",
        \\ExampleAbstract#(.Participant: Type): Contract = ()
        \\
        \\make_value := () -> (.value: ExampleAbstract) {
        \\}
    ,
        null,
        "cannot return contract 'ExampleAbstract' as a runtime value",
        false,
    );
}

test "type rules: polymorphism/16X_abstract_self_output_wrong" {
    try checkSource(
        "polymorphism/16X_abstract_self_output_wrong",
        \\Animal#(.Participant: Type): Contract = (
        \\    .clone : (.who: Participant) -> (.copy: Participant)
        \\)
        \\
        \\Dog := (
        \\    .value : Int32 = 0
        \\)
        \\
        \\_impl_clone_Dog := (.who: Dog) -> (.copy: Int32) {
        \\    copy = who.value
        \\}
        \\
        \\implement Animal#(Dog) (.clone = _impl_clone_Dog)
        \\
        \\main := () -> (.status_code: Int32) {
        \\    status_code = 0
        \\}
    ,
        null,
        "incompatible associated result",
        false,
    );
}

test "type rules: polymorphism/248X_opaque_storage_conditional" {
    try checkSource(
        "polymorphism/248X_opaque_storage_conditional",
        \\Drain#(.Participant: Type): Contract = (
        \\    .drain : (.self: &Participant, .storage: $&Allocation, .value: Int32) -> (.result: ?Int32) where {
        \\        on result ..some { retains(storage, value) }
        \\        on result ..none {}
        \\    }
        \\)
        \\
        \\main := () -> () {}
    ,
        null,
        "conditional opaque storage clauses require correlated hidden storage post-states",
        false,
    );
}

test "type rules: polymorphism/249X_opaque_storage_erased_receiver" {
    try checkSource(
        "polymorphism/249X_opaque_storage_erased_receiver",
        \\Drain#(.Participant: Type): Contract = (
        \\    .drain : (.self: $&Participant) -> () where empties(self)
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Drain#(Cell) (.drain = _impl_drain_Cell)
        \\
        \\_impl_drain_Cell := (.self: $&Cell) -> () { trusted_opaque_mark_empty(self) }
        \\
        \\main := () -> () {
        \\    cell ::= Cell()
        \\    _ ::= to_virtual#(Drain)($&cell)
        \\}
    ,
        null,
        "opaque storage clauses on an erased participant require mapped hidden storage identities",
        false,
    );
}

test "type rules: polymorphism/25X_abstract_overloads_with_defaults_ambiguous" {
    try checkSource(
        "polymorphism/25X_abstract_overloads_with_defaults_ambiguous",
        \\LeftSelection#(.Value: Type): Contract = (
        \\    .pick : (.value: Value, .left: Int32 = 1) -> (.status_code: Int32)
        \\)
        \\
        \\RightSelection#(.Value: Type): Contract = (
        \\    .pick : (.value: Value, .right: Int32 = 2) -> (.status_code: Int32)
        \\)
        \\
        \\_left_pick := (.value: Int32, .left: Int32 = 1) -> (.status_code: Int32) { status_code = left }
        \\
        \\_right_pick := (.value: Int32, .right: Int32 = 2) -> (.status_code: Int32) {
        \\    status_code = right
        \\}
        \\
        \\implement LeftSelection#(Int32) (.pick = _left_pick)
        \\
        \\implement RightSelection#(Int32) (.pick = _right_pick)
        \\
        \\main := () -> (.status_code: Int32) { status_code = pick(.value = 7).status_code }
    ,
        null,
        "multiple applicable operation identities",
        false,
    );
}

test "type rules: polymorphism/267X_internal_storage_readonly_receiver" {
    try checkSource(
        "polymorphism/267X_internal_storage_readonly_receiver",
        \\Protocol#(.Participant: Type): Contract = (
        \\    domain contents
        \\    .clear : (.self: &Participant) -> () where empties(self.contents)
        \\)
        \\
        \\Storage := (.first: Int32)
        \\
        \\implement Protocol#(Storage) (.clear = _impl_clear_Storage) where { contents(self.first) }
        \\
        \\_impl_clear_Storage := (.self: &Storage) -> () {}
        \\
        \\main := () -> () {
        \\    storage ::= Storage(1)
        \\    value ::= to_virtual#(Protocol)(&storage)
        \\}
    ,
        null,
        "retains and empties require mutable storage references",
        false,
    );
}

test "type rules: polymorphism/331X_generic_array_length" {
    try checkSource(
        "polymorphism/331X_generic_array_length",
        \\invalid := #(.T: Type) (.marker: T) -> () {
        \\    bytes: [1]UInt8 = (0, 1)
        \\}
        \\
        \\main := () -> () { invalid#(Int32)(1) }
    ,
        null,
        "array initializer has 2 elements; expected 1",
        false,
    );
}

test "type rules: polymorphism/340X_once_value_alias_reuse" {
    try checkSource(
        "polymorphism/340X_once_value_alias_reuse",
        \\Args: Type = ()
        \\
        \\acquire := once Args -> (.result: Int32) { result = 42 }
        \\alias := acquire
        \\
        \\main := () -> () {
        \\    first ::= acquire()
        \\    second ::= alias()
        \\}
    ,
        null,
        "once function 'acquire' is consumed more than once",
        false,
    );
}

test "type rules: polymorphism/342X_once_generic_value_reuse" {
    try checkSource(
        "polymorphism/342X_once_generic_value_reuse",
        \\acquire := once #(.T: Type) (.value: T) -> (.result: T) {
        \\    result = value
        \\}
        \\
        \\main := () -> () {
        \\    first ::= acquire#(Int32)(.value = 1)
        \\    second ::= acquire#(Int32)(.value = 2)
        \\}
    ,
        null,
        "is consumed more than once",
        false,
    );
}

test "type rules: polymorphism/43X_virtual_multiple_self_receivers" {
    try checkSource(
        "polymorphism/43X_virtual_multiple_self_receivers",
        \\A#(.Participant: Type): Contract = (
        \\    .compare : (.self: &Participant, .other: &Participant) -> (.value: Int32) where {}
        \\)
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.compare = _impl_compare_Box)
        \\
        \\_impl_compare_Box := (.self: &Box, .other: &Box) -> (.value: Int32) { value = self&.value }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A)(.value = $&box)
        \\}
    ,
        null,
        "exactly one borrowed participant receiver",
        false,
    );
}

test "type rules: polymorphism/44X_virtual_self_result" {
    try checkSource(
        "polymorphism/44X_virtual_self_result",
        \\A#(.Participant: Type): Contract = (
        \\    .borrow : (.self: &Participant) -> (.value: &Participant) where depends_on(value, self)
        \\)
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.borrow = _impl_borrow_Box)
        \\
        \\_impl_borrow_Box := (.self: &Box) -> (.value: &Box) { value = self }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A)(.value = $&box)
        \\}
    ,
        null,
        "the hidden participant cannot appear in a virtual operation result",
        false,
    );
}

test "type rules: polymorphism/45X_virtual_self_by_value" {
    try checkSource(
        "polymorphism/45X_virtual_self_by_value",
        \\A#(.Participant: Type): Contract = (.consume: (.self: Participant) -> () where {})
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.consume = _impl_consume_Box)
        \\
        \\_impl_consume_Box := (.self: Box) -> () {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A)(.value = $&box)
        \\}
    ,
        null,
        "the hidden participant is only allowed as a direct borrowed receiver",
        false,
    );
}

test "type rules: polymorphism/46X_virtual_nested_self_input" {
    try checkSource(
        "polymorphism/46X_virtual_nested_self_input",
        \\Nested := #(.T: Type) (.value: &T)
        \\
        \\A#(.Participant: Type): Contract = (
        \\    .inspect : (.self: &Participant, .nested: Nested#(Participant)) -> () where {}
        \\)
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.inspect = _impl_inspect_Box)
        \\
        \\_impl_inspect_Box := (.self: &Box, .nested: Nested#(Box)) -> () {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A)(.value = $&box)
        \\}
    ,
        null,
        "the hidden participant is only allowed as a direct borrowed receiver",
        false,
    );
}

test "type rules: polymorphism/47X_virtual_missing_receiver" {
    try checkSource(
        "polymorphism/47X_virtual_missing_receiver",
        \\A#(.Participant: Type): Contract = (.read: (.value: Int32) -> (.result: Int32) where {})
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.read = _read)
        \\
        \\_read := (.value: Int32) -> (.result: Int32) { result = value }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A)(.value = $&box)
        \\}
    ,
        null,
        "exactly one borrowed participant receiver",
        false,
    );
}

test "type rules: polymorphism/48X_virtual_associated_parameters" {
    try checkSource(
        "polymorphism/48X_virtual_associated_parameters",
        \\A#(.Participant: Type): Contract = (.item: Type)
        \\
        \\Box := (.value: Int32)
        \\
        \\implement A#(Box) (.item: Type = Int32)
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: A#(.item: Float32))(.value = $&box)
        \\}
    ,
        null,
        "incompatible associated elements for the virtual interface",
        false,
    );
}

test "type rules: polymorphism/50X_virtual_readonly_mutable_contract" {
    try checkSource(
        "polymorphism/50X_virtual_readonly_mutable_contract",
        \\Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})
        \\
        \\Box := (.value: Int32)
        \\
        \\implement Counter#(Box) (.bump = _impl_bump_Box)
        \\
        \\_impl_bump_Box := (.self: $&Box) -> () { self&.value = self&.value + 1 }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    readonly ::= &box
        \\    handle ::= to_virtual#(.contract: Counter)(.value = readonly)
        \\    bump(.self = $&handle)
        \\}
    ,
        null,
        "a mutable participant receiver requires a mutable concrete reference",
        false,
    );
}

test "type rules: polymorphism/51X_virtual_readonly_generic_conversion" {
    try checkSource(
        "polymorphism/51X_virtual_readonly_generic_conversion",
        \\Counter#(.Participant: Type): Contract = (.bump: (.self: $&Participant) -> () where {})
        \\
        \\Box := (.value: Int32)
        \\
        \\implement Counter#(Box) (.bump = _impl_bump_Box)
        \\
        \\_impl_bump_Box := (.self: $&Box) -> () { self&.value = self&.value + 1 }
        \\
        \\wrap := #(.t: Type: Counter) (.value: &t) -> (.result: Virtual#(.contract: Counter)) {
        \\    result = to_virtual#(.contract: Counter)(.value = value)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 7)
        \\    handle ::= wrap#(.t: Box)(.value = &box).result
        \\    bump(.self = $&handle)
        \\}
    ,
        null,
        "a mutable participant receiver requires a mutable concrete reference",
        false,
    );
}

test "type rules: polymorphism/53X_virtual_bound_value_mismatch" {
    try checkSource(
        "polymorphism/53X_virtual_bound_value_mismatch",
        \\Fixed#(.Participant: Type): Contract = (.n: Int)
        \\
        \\Box := (.value: Int32)
        \\
        \\implement Fixed#(Box) (.n: Int = 1)
        \\
        \\main := () -> () {
        \\    box :: Box = (.value = 7)
        \\    handle ::= to_virtual#(.contract: Fixed#(.n = 2))(.value = &box)
        \\}
    ,
        null,
        "incompatible associated elements for the virtual interface",
        false,
    );
}

test "type rules: polymorphism/66X_contextual_choice_ambiguous" {
    try checkSource(
        "polymorphism/66X_contextual_choice_ambiguous",
        \\First: Type = (..before, ..shared)
        \\
        \\Second: Type = (..shared, ..after)
        \\
        \\FirstSelection#(.Number: Type): Contract = (
        \\    .Tag    : Type
        \\    .select : (.tag: Tag, .number: Number) -> (.value: Int32)
        \\)
        \\
        \\SecondSelection#(.Number: Type): Contract = (
        \\    .Tag    : Type
        \\    .select : (.tag: Tag, .number: Number) -> (.value: Int32)
        \\)
        \\
        \\_first_select := (.tag: First, .number: Int32) -> (.value: Int32) { value = 1 }
        \\
        \\_second_select := (.tag: Second, .number: Int32) -> (.value: Int32) { value = 2 }
        \\
        \\implement FirstSelection#(Int32) (.Tag: Type = First, .select = _first_select)
        \\
        \\implement SecondSelection#(Int32) (.Tag: Type = Second, .select = _second_select)
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    number: Int32 = 1
        \\    value := select(.tag = ..shared, .number = number)
        \\}
    ,
        null,
        "multiple applicable operation identities",
        false,
    );
}

test "type rules: polymorphism/70X_virtual_safety_contract_unknown_name" {
    try checkSource(
        "polymorphism/70X_virtual_safety_contract_unknown_name",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.value: &Int32)
        \\    where depends_on(value, missing)
        \\)
        \\
        \\main := () -> () {}
    ,
        null,
        "depends_on dependencies must name method inputs",
        false,
    );
}

test "type rules: polymorphism/74X_virtual_safety_contract_output_name" {
    try checkSource(
        "polymorphism/74X_virtual_safety_contract_output_name",
        \\Source#(.Participant: Type): Contract = (
        \\    .get : (.self: &Participant) -> (.value: &Int32)
        \\    where depends_on(self, value)
        \\)
        \\
        \\main := () -> () {}
    ,
        null,
        "the first depends_on argument must name a method output",
        false,
    );
}

test "type rules: polymorphism/80X_virtual_safety_contract_referent_type" {
    try checkSource(
        "polymorphism/80X_virtual_safety_contract_referent_type",
        \\Forwarder#(.Participant: Type): Contract = (
        \\    .forward : (.self: &Participant, .input: $&Int32) -> (.value: &UInt8)
        \\    where refers_to(value, input)
        \\)
        \\
        \\Cell := (.unused: Int32)
        \\
        \\implement Forwarder#(Cell) (.forward = _impl_forward_Cell)
        \\
        \\global :: UInt8 = 0
        \\
        \\_impl_forward_Cell := (.self: &Cell, .input: $&Int32) -> (.value: &UInt8) {
        \\    value = &global
        \\}
        \\
        \\main := () -> () {
        \\    cell ::= Cell(0)
        \\    handle ::= to_virtual#(Forwarder)(&cell)
        \\}
    ,
        null,
        "matching input and output referent types",
        false,
    );
}

test "type rules: polymorphism/81X_virtual_safety_contract_referent_mutability" {
    try checkSource(
        "polymorphism/81X_virtual_safety_contract_referent_mutability",
        \\Forwarder#(.Participant: Type): Contract = (
        \\    .forward : (.self: &Participant, .input: &Int32) -> (.value: $&Int32)
        \\    where refers_to(value, input)
        \\)
        \\
        \\Cell := (.unused: Int32)
        \\
        \\implement Forwarder#(Cell) (.forward = _impl_forward_Cell)
        \\
        \\global :: Int32 = 0
        \\
        \\_impl_forward_Cell := (.self: &Cell, .input: &Int32) -> (.value: $&Int32) {
        \\    value = $&global
        \\}
        \\
        \\main := () -> () {
        \\    cell ::= Cell(0)
        \\    handle ::= to_virtual#(Forwarder)(&cell)
        \\}
    ,
        null,
        "cannot grant mutable access",
        false,
    );
}

test "type rules: polymorphism/84X_virtual_safety_contract_invalidate_readonly" {
    try checkSource(
        "polymorphism/84X_virtual_safety_contract_invalidate_readonly",
        \\Editor#(.Participant: Type): Contract = (
        \\    .edit : (.self: &Participant, .target: &Int32) -> ()
        \\    where invalidates(target)
        \\)
        \\
        \\Cell := (.unused: Int32)
        \\
        \\implement Editor#(Cell) (.edit = _impl_edit_Cell)
        \\
        \\_impl_edit_Cell := (.self: &Cell, .target: &Int32) -> () {
        \\
        \\}
        \\
        \\apply_edit := (.editor: &Virtual#(Editor), .target: &Int32) -> () {
        \\    edit(editor, target)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    cell ::= Cell(0)
        \\    target :: Int32 = 41
        \\    editor ::= to_virtual#(Editor)(&cell)
        \\    apply_edit(&editor, $&target)
        \\
        \\    if target != 42 {
        \\        status_code = 1
        \\    }
        \\}
    ,
        null,
        "invalidates requires a mutable reference input",
        false,
    );
}

test "type rules: polymorphism/85X_virtual_safety_contract_invalidate_self" {
    try checkSource(
        "polymorphism/85X_virtual_safety_contract_invalidate_self",
        \\Editor#(.Participant: Type): Contract = (
        \\    .edit : (.self: $&Participant) -> () where invalidates(self)
        \\)
        \\
        \\Cell := (.unused: Int32)
        \\
        \\implement Editor#(Cell) (.edit = _impl_edit_Cell)
        \\
        \\_impl_edit_Cell := (.self: $&Cell) -> () {}
        \\
        \\main := () -> () {
        \\    cell ::= Cell(0)
        \\    editor ::= to_virtual#(Editor)($&cell)
        \\}
    ,
        null,
        "invalidating an erased receiver requires a mapped storage domain",
        false,
    );
}

test "type rules: polymorphism/89X_virtual_safety_contract_domain_overlap" {
    try checkSource(
        "polymorphism/89X_virtual_safety_contract_domain_overlap",
        \\Source#(.Participant: Type): Contract = (
        \\    domain storage
        \\    domain sibling
        \\    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
        \\    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
        \\)
        \\
        \\Cell := (.value: Int32, .other: Int32)
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell, .reset = _impl_reset_Cell) where {
        \\    storage(self.value)
        \\    sibling(self.value)
        \\}
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
        \\    value = &self&.value
        \\}
        \\
        \\_impl_reset_Cell := (.self: $&Cell) -> () {
        \\    self&.value = 42
        \\}
        \\
        \\borrow := (.source: &Virtual#(Source)) -> (.value: &Int32) {
        \\    value = get(source)
        \\}
        \\
        \\reset_source := (.source: $&Virtual#(Source)) -> () {
        \\    reset(source)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    cell ::= Cell(41, 9)
        \\    source ::= to_virtual#(Source)($&cell)
        \\    before ::= borrow(&source)
        \\    if before&!= 41 { status_code = 1 }
        \\    reset_source($&source)
        \\    after ::= borrow(&source)
        \\    if after&!= 42 { status_code = 1 }
        \\}
    ,
        null,
        "storage domains overlap",
        false,
    );
}

test "type rules: polymorphism/90X_virtual_safety_contract_domain_missing" {
    try checkSource(
        "polymorphism/90X_virtual_safety_contract_domain_missing",
        \\Source#(.Participant: Type): Contract = (
        \\    domain storage
        \\    .get   : (.self: &Participant) -> (.value: &Int32) where depends_on(value, self.storage)
        \\    .reset : (.self: $&Participant) -> () where invalidates(self.storage)
        \\)
        \\
        \\Cell := (.value: Int32, .other: Int32)
        \\
        \\implement Source#(Cell) (.get = _impl_get_Cell, .reset = _impl_reset_Cell)
        \\
        \\_impl_get_Cell := (.self: &Cell) -> (.value: &Int32) {
        \\    value = &self&.value
        \\}
        \\
        \\_impl_reset_Cell := (.self: $&Cell) -> () {
        \\    self&.value = 42
        \\}
        \\
        \\borrow := (.source: &Virtual#(Source)) -> (.value: &Int32) {
        \\    value = get(source)
        \\}
        \\
        \\reset_source := (.source: $&Virtual#(Source)) -> () {
        \\    reset(source)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    cell ::= Cell(41, 9)
        \\    source ::= to_virtual#(Source)($&cell)
        \\    before ::= borrow(&source)
        \\    if before&!= 41 { status_code = 1 }
        \\    reset_source($&source)
        \\    after ::= borrow(&source)
        \\    if after&!= 42 { status_code = 1 }
        \\}
    ,
        null,
        "every Contract storage domain requires exactly one implementation mapping",
        false,
    );
}

test "type rules: types/281X_positional_type_after_named" {
    try checkSyntaxSource(
        "types/281X_positional_type_after_named",
        \\Pair := #(.left: Type, .right: Type ) (.left: left, .right: right)
        \\main := () -> () { value: Pair#(.left: Int32, Bool) = (.left = 1, .right = true) }
    ,
        "positional type arguments must appear before named arguments",
    );
}

test "type rules: types/282X_positional_type_duplicate" {
    try checkSource(
        "types/282X_positional_type_duplicate",
        \\Pair := #(.left: Type, .right: Type) (.left: left, .right: right)
        \\
        \\main := () -> () { value: Pair#(Int32, .left: Bool) = (.left = 1, .right = true) }
    ,
        null,
        "duplicate generic argument",
        false,
    );
}

test "type rules: types/283X_positional_type_excess" {
    try checkSource(
        "types/283X_positional_type_excess",
        \\Pair := #(.left: Type, .right: Type) (.left: left, .right: right)
        \\
        \\main := () -> () { value: Pair#(Int32, Bool, UInt8) = (.left = 1, .right = true) }
    ,
        null,
        "too many generic arguments",
        false,
    );
}

test "type rules: types/284X_positional_type_missing" {
    try checkSource(
        "types/284X_positional_type_missing",
        \\Pair := #(.left: Type, .right: Type) (.left: left, .right: right)
        \\
        \\main := () -> () { value: Pair#(Int32) = (.left = 1, .right = true) }
    ,
        null,
        "missing required generic argument",
        false,
    );
}

test "type rules: types/285X_positional_type_kind" {
    try checkSource(
        "types/285X_positional_type_kind",
        \\Box := #(.t: Type) (.value: t)
        \\
        \\main := () -> () { value: Box#(4) = (.value = 1) }
    ,
        null,
        "generic argument kind does not match its parameter",
        false,
    );
}

test "type rules: types/286X_positional_type_unknown" {
    try checkSource(
        "types/286X_positional_type_unknown",
        \\Box := #(.t: Type) (.value: t)
        \\
        \\main := () -> () { value: Box#(.other: Int32) = (.value = 1) }
    ,
        null,
        "unknown generic argument",
        false,
    );
}

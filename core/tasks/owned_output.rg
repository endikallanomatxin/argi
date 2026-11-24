-- The reservation protects raw storage before submission. Once a worker
-- accepts it, custody must go to either the receipt or a typed output owner.
_TaskOutputReservation := (._slot: UIntNative, ._ffi: $&ForeignFunctionInterface)

-- After request completion and native release, the typed owner can claim
-- an occupied slot exactly once.
_OwnedTaskOutput := #(.T: Type) (._slot: UIntNative, ._entry: _TaskEntry, ._ffi: $&ForeignFunctionInterface)

_new_task_output(.entry: _TaskEntry) -> (.slot: UIntNative): CFunction(.symbol = "_argi_task_output_create") where { no_access() }
_task_output_accepted(.slot: UIntNative, .entry: _TaskEntry) -> (.accepted: CInt): CFunction(.symbol = "_argi_task_output_accepted") where { no_access() }
_detach_task_output(.slot: UIntNative, .task: UIntNative, .entry: _TaskEntry) -> (.status: CInt): CFunction(.symbol = "_argi_task_output_detach") where { no_access() }
_claim_task_output(.slot: UIntNative, .entry: _TaskEntry) -> (.address: UIntNative): CFunction(.symbol = "_argi_task_output_take") where { no_access() }
_destroy_task_output(.slot: UIntNative) -> (.status: CInt): CFunction(.symbol = "_argi_task_output_destroy") where { no_access() }

_reserve_task_output := (.entry: _TaskEntry, .ffi: $&ForeignFunctionInterface) -> (
    .result: Errable#(_TaskOutputReservation, (..task_start_failed))
) {
    slot ::= _new_task_output(.entry = entry, .ffi = ffi)
    if slot == 0 {
        result = ..error(.reason = ..task_start_failed)
        return
    }
    result = ..ok(._slot = slot, ._ffi = ffi)
}

implement Deinit#(_TaskOutputReservation) (
    .deinit = (.self: $&_TaskOutputReservation) -> () {
        if self&._slot == 0 { return }
        if _destroy_task_output(.slot = self&._slot, .ffi = self&._ffi) != 0 { abort }
    }
)

_adopt_task_output := #(.T: Type) (.reservation: $&_TaskOutputReservation, .entry: _TaskEntry) -> (
    .output: _OwnedTaskOutput#(T)
) {
    output = (._slot = reservation&._slot, ._entry = entry, ._ffi = reservation&._ffi)
    reservation&._slot = 0
}

implement#(.T: Type) Deinit#(_OwnedTaskOutput#(T)) (
    .deinit = (.self: $&_OwnedTaskOutput#(T)) -> () {
        if self&._slot == 0 { return }
        assume ffi := self&._ffi
        #if is_plain_data(.type = T) {
            _ = _claim_task_output(.slot = self&._slot, .entry = self&._entry)
        } #else {
            address ::= _claim_task_output(.slot = self&._slot, .entry = self&._entry)
            if address != 0 {
                discarded ::= _extract_task_output#(T)(.self = self, .address = address)
            }
        }
        if _destroy_task_output(.slot = self&._slot) != 0 { abort }
    }
)

-- A closed receipt transfers its output slot to exactly one typed owner.
_withdraw_task_output := #(.T: Type) (.task: $&TaskReceipt) -> (.output: _OwnedTaskOutput#(T)) {
    if task&._handle != 0 { abort }
    output = (._slot = task&._output_slot, ._entry = task&._entry, ._ffi = task&._ffi)
    task&._output_slot = 0
}

_take_task_output := #(.T: Type) (.self: $&_OwnedTaskOutput#(T)) -> (.result: T) {
    address ::= _claim_task_output(.ffi = self&._ffi, .slot = self&._slot, .entry = self&._entry)
    if address == 0 { abort }
    result = _extract_task_output#(T)(.self = self, .address = address)
}

-- The caller obtained address from a successful one-shot claim on self.
-- Extraction transfers cleanup to the ordinary typed lexical owner.
_extract_task_output := #(.T: Type) (.self: $&_OwnedTaskOutput#(T), .address: UIntNative) -> (.result: T) {
    anchor ::= erase_reference#(_OwnedTaskOutput#(T))(.base = self)
    slot ::= trusted_establish_inherited_reference#(T)(.raw = raw_pointer#(T)(.address = address), .root = anchor)
    result = trusted_opaque_move_out#(.t: T, .storage_type: _OwnedTaskOutput#(T))(.storage = self, .slot = slot)
}

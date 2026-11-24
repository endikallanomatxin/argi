-- This owner is constructed before submit. After request completion and native
-- receipt release, an occupied slot can be claimed exactly once. The typed
-- caller performs cleanup; releasing the native slot only frees its buffer.
_OwnedTaskOutput := #(.T: Type) (._slot: UIntNative, ._entry: _TaskEntry, ._ffi: $&ForeignFunctionInterface)

_new_task_output(.entry: _TaskEntry) -> (.slot: UIntNative): CFunction(.symbol = "_argi_task_output_create") where { no_access() }
_task_output_accepted(.slot: UIntNative, .entry: _TaskEntry) -> (.accepted: CInt): CFunction(.symbol = "_argi_task_output_accepted") where { no_access() }
_detach_task_output(.slot: UIntNative, .task: UIntNative, .entry: _TaskEntry) -> (.status: CInt): CFunction(.symbol = "_argi_task_output_detach") where { no_access() }
_claim_task_output(.slot: UIntNative, .entry: _TaskEntry) -> (.address: UIntNative): CFunction(.symbol = "_argi_task_output_take") where { no_access() }
_destroy_task_output(.slot: UIntNative) -> (.status: CInt): CFunction(.symbol = "_argi_task_output_destroy") where { no_access() }

_prepare_task_output := #(.T: Type) (.entry: _TaskEntry, .ffi: $&ForeignFunctionInterface) -> (
    .result: Errable#(_OwnedTaskOutput#(T), (..task_start_failed))
) {
    slot ::= _new_task_output(.entry = entry, .ffi = ffi)
    if slot == 0 {
        result = ..error(.reason = ..task_start_failed)
        return
    }
    result = ..ok(._slot = slot, ._entry = entry, ._ffi = ffi)
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
                anchor ::= erase_reference#(_OwnedTaskOutput#(T))(.base = self)
                slot ::= trusted_establish_inherited_reference#(T)(.raw = raw_pointer#(T)(.address = address), .root = anchor)
                trusted_opaque_drop#(.t: T)(.slot = slot)
            }
        }
        if _destroy_task_output(.slot = self&._slot) != 0 { abort }
    }
)

_take_task_output := #(.T: Type) (.self: $&_OwnedTaskOutput#(T)) -> (.result: T) {
    address ::= _claim_task_output(.ffi = self&._ffi, .slot = self&._slot, .entry = self&._entry)
    if address == 0 { abort }
    anchor ::= erase_reference#(_OwnedTaskOutput#(T))(.base = self)
    slot ::= trusted_establish_inherited_reference#(T)(.raw = raw_pointer#(T)(.address = address), .root = anchor)
    result = trusted_opaque_move_out#(.t: T, .storage_type: _OwnedTaskOutput#(T))(.storage = self, .slot = slot)
}

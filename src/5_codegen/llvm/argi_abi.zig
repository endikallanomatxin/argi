const c = @import("llvm.zig").c;

// Argi's private calling convention. C imports/exports use their target-specific
// ABI instead. Definitions, ordinary calls and virtual calls share this plan;
// internal parameters must never be inserted independently at a call site.
pub const EvidenceTypes = struct {
    input: ?c.LLVMTypeRef = null,
    output: ?c.LLVMTypeRef = null,
};

pub const CallEvidence = struct {
    input: ?c.LLVMValueRef = null,
    output_storage: ?c.LLVMValueRef = null,
};

pub const Signature = struct {
    function_type: c.LLVMTypeRef,
    input_type: c.LLVMTypeRef,
    output_type: c.LLVMTypeRef,
    indirect_output: bool,
    evidence: EvidenceTypes,

    pub fn init(input_type: c.LLVMTypeRef, output_type: c.LLVMTypeRef, indirect_output: bool) Signature {
        return initWithEvidence(input_type, output_type, indirect_output, .{});
    }

    // Evidence has its own typed channel; it is neither a language field nor
    // reconstructed from value addresses. Omitted channels add no parameters.
    // Output evidence uses caller storage even when the value returns in SSA.
    pub fn initWithEvidence(input_type: c.LLVMTypeRef, output_type: c.LLVMTypeRef, indirect_output: bool, evidence: EvidenceTypes) Signature {
        var parameters: [4]c.LLVMTypeRef = undefined;
        var count: u32 = 0;
        if (indirect_output) {
            parameters[count] = c.LLVMPointerType(output_type, 0);
            count += 1;
        }
        parameters[count] = input_type;
        count += 1;
        if (evidence.input) |ty| {
            parameters[count] = ty;
            count += 1;
        }
        if (evidence.output) |ty| {
            parameters[count] = c.LLVMPointerType(ty, 0);
            count += 1;
        }
        return .{
            .function_type = c.LLVMFunctionType(if (indirect_output) c.LLVMVoidType() else output_type, &parameters, count, 0),
            .input_type = input_type,
            .output_type = output_type,
            .indirect_output = indirect_output,
            .evidence = evidence,
        };
    }

    fn inputIndex(self: Signature) u32 {
        return @intFromBool(self.indirect_output);
    }

    pub fn input(self: Signature, function: c.LLVMValueRef) c.LLVMValueRef {
        return c.LLVMGetParam(function, self.inputIndex());
    }

    pub fn inputEvidence(self: Signature, function: c.LLVMValueRef) ?c.LLVMValueRef {
        return if (self.evidence.input != null) c.LLVMGetParam(function, self.inputIndex() + 1) else null;
    }

    pub fn outputStorage(self: Signature, function: c.LLVMValueRef) ?c.LLVMValueRef {
        return if (self.indirect_output) c.LLVMGetParam(function, 0) else null;
    }

    pub fn outputEvidenceStorage(self: Signature, function: c.LLVMValueRef) ?c.LLVMValueRef {
        return if (self.evidence.output != null)
            c.LLVMGetParam(function, self.inputIndex() + 1 + @as(u32, @intFromBool(self.evidence.input != null)))
        else
            null;
    }

    pub fn returnValue(self: Signature, builder: c.LLVMBuilderRef, function: c.LLVMValueRef, value: c.LLVMValueRef) !void {
        return self.returnWithEvidence(builder, function, value, null);
    }

    pub fn returnWithEvidence(self: Signature, builder: c.LLVMBuilderRef, function: c.LLVMValueRef, value: c.LLVMValueRef, evidence: ?c.LLVMValueRef) !void {
        if (c.LLVMTypeOf(value) != self.output_type) return error.InvalidArgiReturnValue;
        if (self.evidence.output) |ty| {
            const supplied = evidence orelse return error.MissingArgiReturnEvidence;
            if (c.LLVMTypeOf(supplied) != ty) return error.InvalidArgiReturnEvidence;
        } else if (evidence != null) return error.UnexpectedArgiReturnEvidence;
        // Validate the entire return before emitting either write.
        if (evidence) |supplied| _ = c.LLVMBuildStore(builder, supplied, self.outputEvidenceStorage(function).?);
        if (self.outputStorage(function)) |storage| {
            _ = c.LLVMBuildStore(builder, value, storage);
            _ = c.LLVMBuildRetVoid(builder);
        } else _ = c.LLVMBuildRet(builder, value);
    }

    // The caller owns output-storage policy: ordinary expressions allocate a
    // temporary, while large-value forwarding supplies its checked destination.
    // An indirect call returns no SSA aggregate to load or repack unnecessarily.
    pub fn call(self: Signature, builder: c.LLVMBuilderRef, callee: c.LLVMValueRef, argument: c.LLVMValueRef, destination: ?c.LLVMValueRef, name: [:0]const u8) !?c.LLVMValueRef {
        return self.callWithEvidence(builder, callee, argument, destination, .{}, name);
    }

    pub fn callWithEvidence(self: Signature, builder: c.LLVMBuilderRef, callee: c.LLVMValueRef, argument: c.LLVMValueRef, destination: ?c.LLVMValueRef, evidence: CallEvidence, name: [:0]const u8) !?c.LLVMValueRef {
        if (c.LLVMTypeOf(argument) != self.input_type) return error.InvalidArgiCallInput;
        if (self.indirect_output) {
            const storage = destination orelse return error.MissingArgiOutputStorage;
            if (c.LLVMGetTypeKind(c.LLVMTypeOf(storage)) != c.LLVMPointerTypeKind) return error.InvalidArgiOutputStorage;
        } else if (destination != null) return error.UnexpectedArgiOutputStorage;
        if (self.evidence.input) |ty| {
            const supplied = evidence.input orelse return error.MissingArgiInputEvidence;
            if (c.LLVMTypeOf(supplied) != ty) return error.InvalidArgiInputEvidence;
        } else if (evidence.input != null) return error.UnexpectedArgiInputEvidence;
        if (self.evidence.output != null) {
            const storage = evidence.output_storage orelse return error.MissingArgiOutputEvidenceStorage;
            if (c.LLVMGetTypeKind(c.LLVMTypeOf(storage)) != c.LLVMPointerTypeKind) return error.InvalidArgiOutputEvidenceStorage;
        } else if (evidence.output_storage != null) return error.UnexpectedArgiOutputEvidenceStorage;
        // Keep parameter assembly in the same order as signature construction.
        var args: [4]c.LLVMValueRef = undefined;
        var count: u32 = 0;
        if (destination) |storage| {
            args[count] = storage;
            count += 1;
        }
        args[count] = argument;
        count += 1;
        if (evidence.input) |supplied| {
            args[count] = supplied;
            count += 1;
        }
        if (evidence.output_storage) |storage| {
            args[count] = storage;
            count += 1;
        }
        const result = c.LLVMBuildCall2(builder, self.function_type, callee, &args, count, if (self.indirect_output) "" else name.ptr);
        return if (self.indirect_output) null else result;
    }
};

test "Argi ABI verifies calls and definitions with both result conventions" {
    const std = @import("std");
    const module = c.LLVMModuleCreateWithName("argi_abi_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    var input_fields = [_]c.LLVMTypeRef{c.LLVMInt32Type()};
    const input_type = c.LLVMStructType(&input_fields, 1, 0);
    for ([_]bool{ false, true }) |indirect| {
        var output_fields = [_]c.LLVMTypeRef{if (indirect) c.LLVMArrayType(c.LLVMInt32Type(), 40) else c.LLVMInt32Type()};
        const output_type = c.LLVMStructType(&output_fields, 1, 0);
        const signature = Signature.init(input_type, output_type, indirect);
        var legacy_parameters = [_]c.LLVMTypeRef{ c.LLVMPointerType(output_type, 0), input_type };
        const legacy_type = if (indirect)
            c.LLVMFunctionType(c.LLVMVoidType(), &legacy_parameters, 2, 0)
        else
            c.LLVMFunctionType(output_type, &legacy_parameters[1], 1, 0);
        try std.testing.expectEqual(legacy_type, signature.function_type);
        const callee = c.LLVMAddFunction(module, if (indirect) "indirect_callee" else "direct_callee", signature.function_type);
        c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(callee, "entry"));
        try std.testing.expectEqual(input_type, c.LLVMTypeOf(signature.input(callee)));
        try std.testing.expectError(error.InvalidArgiReturnValue, signature.returnValue(builder, callee, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0)));
        try signature.returnValue(builder, callee, c.LLVMConstNull(output_type));

        const caller = c.LLVMAddFunction(module, if (indirect) "indirect_caller" else "direct_caller", signature.function_type);
        c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(caller, "entry"));
        const destination = signature.outputStorage(caller);
        const result = try signature.call(builder, callee, signature.input(caller), destination, "result");
        if (indirect) {
            try std.testing.expect(result == null);
            try std.testing.expectError(error.MissingArgiOutputStorage, signature.call(builder, callee, signature.input(caller), null, ""));
            try std.testing.expectError(error.InvalidArgiOutputStorage, signature.call(builder, callee, signature.input(caller), c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), ""));
            _ = c.LLVMBuildRetVoid(builder);
        } else {
            try std.testing.expect(result != null);
            try std.testing.expectError(error.UnexpectedArgiOutputStorage, signature.call(builder, callee, signature.input(caller), c.LLVMConstNull(c.LLVMPointerType(output_type, 0)), ""));
            _ = c.LLVMBuildRet(builder, result.?);
        }
        try std.testing.expectError(error.InvalidArgiCallInput, signature.call(builder, callee, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), destination, ""));
    }
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}

test "Argi ABI transports separate input and output evidence with either value convention" {
    const std = @import("std");
    const module = c.LLVMModuleCreateWithName("argi_evidence_abi_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    const pointer = c.LLVMPointerType(c.LLVMInt8Type(), 0);
    var value_fields = [_]c.LLVMTypeRef{ pointer, pointer };
    const input_type = c.LLVMStructType(&value_fields, 2, 0);
    // The two references can share a value address while their obligations
    // have different identities. Evidence must remain an independent channel.
    var evidence_fields = [_]c.LLVMTypeRef{ pointer, pointer, c.LLVMInt64Type() };
    const input_evidence_type = c.LLVMStructType(&evidence_fields, 3, 0);
    const output_evidence_type = c.LLVMArrayType(pointer, 2);
    const invalid_value = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
    for ([_]bool{ false, true }) |indirect| {
        const output_type = if (indirect) c.LLVMArrayType(c.LLVMInt32Type(), 40) else input_type;
        for (0..4) |channels| {
            const signature = Signature.initWithEvidence(input_type, output_type, indirect, .{
                .input = if (channels & 1 != 0) input_evidence_type else null,
                .output = if (channels & 2 != 0) output_evidence_type else null,
            });
            const name = try std.fmt.allocPrintSentinel(std.testing.allocator, "evidence_{d}_{d}", .{ @intFromBool(indirect), channels }, 0);
            defer std.testing.allocator.free(name);
            const callee = c.LLVMAddFunction(module, name.ptr, signature.function_type);
            c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(callee, "entry"));
            try std.testing.expectEqual(input_type, c.LLVMTypeOf(signature.input(callee)));
            var evidence: ?c.LLVMValueRef = if (signature.evidence.output != null) c.LLVMConstNull(output_evidence_type) else null;
            if (signature.inputEvidence(callee)) |received| {
                try std.testing.expectEqual(input_evidence_type, c.LLVMTypeOf(received));
                if (evidence != null) {
                    evidence = c.LLVMBuildInsertValue(builder, evidence.?, c.LLVMBuildExtractValue(builder, received, 0, "first.flag"), 0, "first.evidence");
                    evidence = c.LLVMBuildInsertValue(builder, evidence.?, c.LLVMBuildExtractValue(builder, received, 1, "second.flag"), 1, "second.evidence");
                }
            } else try std.testing.expect(signature.evidence.input == null);
            const before = c.LLVMGetLastInstruction(c.LLVMGetInsertBlock(builder));
            if (signature.evidence.output != null) {
                try std.testing.expect(signature.outputEvidenceStorage(callee) != null);
                try std.testing.expectError(error.MissingArgiReturnEvidence, signature.returnValue(builder, callee, c.LLVMConstNull(output_type)));
                try std.testing.expectError(error.InvalidArgiReturnEvidence, signature.returnWithEvidence(builder, callee, c.LLVMConstNull(output_type), invalid_value));
            } else {
                try std.testing.expect(signature.outputEvidenceStorage(callee) == null);
                try std.testing.expectError(error.UnexpectedArgiReturnEvidence, signature.returnWithEvidence(builder, callee, c.LLVMConstNull(output_type), invalid_value));
            }
            // Rejected emission must not leave one half of a return behind.
            try std.testing.expectEqual(before, c.LLVMGetLastInstruction(c.LLVMGetInsertBlock(builder)));
            try signature.returnWithEvidence(builder, callee, c.LLVMConstNull(output_type), evidence);

            const caller_name = try std.fmt.allocPrintSentinel(std.testing.allocator, "caller_{s}", .{name}, 0);
            defer std.testing.allocator.free(caller_name);
            const caller = c.LLVMAddFunction(module, caller_name.ptr, signature.function_type);
            c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(caller, "entry"));
            const supplied: CallEvidence = .{ .input = signature.inputEvidence(caller), .output_storage = signature.outputEvidenceStorage(caller) };
            const argument = signature.input(caller);
            const destination = signature.outputStorage(caller);
            if (signature.evidence.input != null) {
                var missing = supplied;
                missing.input = null;
                try std.testing.expectError(error.MissingArgiInputEvidence, signature.callWithEvidence(builder, callee, argument, destination, missing, ""));
                missing.input = invalid_value;
                try std.testing.expectError(error.InvalidArgiInputEvidence, signature.callWithEvidence(builder, callee, argument, destination, missing, ""));
            } else {
                var unexpected = supplied;
                unexpected.input = invalid_value;
                try std.testing.expectError(error.UnexpectedArgiInputEvidence, signature.callWithEvidence(builder, callee, argument, destination, unexpected, ""));
            }
            if (signature.evidence.output != null) {
                var missing = supplied;
                missing.output_storage = null;
                try std.testing.expectError(error.MissingArgiOutputEvidenceStorage, signature.callWithEvidence(builder, callee, argument, destination, missing, ""));
                missing.output_storage = invalid_value;
                try std.testing.expectError(error.InvalidArgiOutputEvidenceStorage, signature.callWithEvidence(builder, callee, argument, destination, missing, ""));
            } else {
                var unexpected = supplied;
                unexpected.output_storage = c.LLVMConstNull(pointer);
                try std.testing.expectError(error.UnexpectedArgiOutputEvidenceStorage, signature.callWithEvidence(builder, callee, argument, destination, unexpected, ""));
            }
            try std.testing.expect(c.LLVMGetLastInstruction(c.LLVMGetInsertBlock(builder)) == null);
            const result = try signature.callWithEvidence(builder, callee, argument, destination, supplied, "result");
            try std.testing.expectEqual(indirect, result == null);
            const value = if (result) |ssa| ssa else c.LLVMBuildLoad2(builder, output_type, destination.?, "returned.value");
            const returned_evidence: ?c.LLVMValueRef = if (supplied.output_storage) |storage| c.LLVMBuildLoad2(builder, output_evidence_type, storage, "returned.evidence") else null;
            try signature.returnWithEvidence(builder, caller, value, returned_evidence);
        }
    }
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}

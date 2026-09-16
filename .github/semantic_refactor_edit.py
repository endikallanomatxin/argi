from pathlib import Path

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''            .resolve_match => |value| resolution.Result.fromBool(try self.resolveMatch(module, o, value)),
'''
new = '''            .resolve_match => |value| try self.resolveMatch(module, o, value),
'''
if text.count(old) != 1:
    raise RuntimeError(f"match dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

start = text.index("    fn resolveMatch(")
end = text.index("\n    fn matchCaseAlreadyResolved", start)
new_function = '''    fn resolveMatch(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const expression = globalizer.globalNode(o, value.value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(expression)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(choice_ty)) return .deferred;
        const variants = types.variants(self.graph, choice_ty) orelse return .invalid;
        const local_cases = module.semantic.node_refs.items[value.cases.start..][0..value.cases.len];

        // Validate the complete pattern set before mutating the global graph.
        // A terminal-invalid case must not leave partially materialized switch
        // cases or payload binding types behind for later fixed-point rounds.
        var seen: std.ArrayList(global_sg.GlobalVariantId) = .empty;
        defer seen.deinit(self.allocator);
        for (local_cases) |local_case_node| {
            const local_node = module.semantic.nodes.items[@intFromEnum(local_case_node)];
            const pending_id = switch (local_node) {
                .pending => |id| id,
                else => return .deferred,
            };
            const pending = module.semantic.pending_operations.items[@intFromEnum(pending_id)];
            const case = switch (pending) {
                .resolve_match_case => |item| item,
                else => return .deferred,
            };
            const option_ref = module.semantic.external_refs.items[@intFromEnum(case.option)];
            const option_name = module.text(option_ref.name);
            const hit = types.findVariant(self.graph, choice_ty, option_name) orelse return .invalid;
            for (seen.items) |previous| if (previous == hit.id) return .invalid;
            try seen.append(self.allocator, hit.id);
            if (case.payload_binding != null and hit.variant.payload_type == null) return .invalid;
            if (case.payload_binding == null and hit.variant.payload_type != null) return .invalid;
        }

        const case_start: u32 = @intCast(self.graph.switch_cases.items.len);
        for (local_cases) |local_case_node| {
            const pending_id = switch (module.semantic.nodes.items[@intFromEnum(local_case_node)]) {
                .pending => |id| id,
                else => unreachable,
            };
            const case = module.semantic.pending_operations.items[@intFromEnum(pending_id)].resolve_match_case;
            const option_ref = module.semantic.external_refs.items[@intFromEnum(case.option)];
            const hit = types.findVariant(self.graph, choice_ty, module.text(option_ref.name)).?;

            if (case.payload_binding) |local_binding| {
                const payload_ty = hit.variant.payload_type.?;
                const binding = globalizer.globalBinding(o, local_binding);
                self.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload_ty, case.mode);
            }

            const tag = try self.appendIntNode(hit.variant.value, self.sourceFor(option_ref.source, o));
            try self.graph.switch_cases.append(self.allocator, .{
                .value = tag,
                .variant = hit.id,
                .body = globalizer.globalBlock(o, case.body),
                .payload_binding = if (case.payload_binding) |binding| globalizer.globalBinding(o, binding) else null,
                .payload_mode = case.mode,
            });
            const global_case_node = globalizer.globalNode(o, case.node);
            self.graph.nodes.items[@intFromEnum(global_case_node)] = .{
                .source = self.sourceFor(option_ref.source, o),
                .ty = try self.builtin(.Void),
                .content = .{ .code_block = globalizer.globalBlock(o, case.body) },
            };
        }

        const switch_id: global_sg.GlobalSwitchId = @enumFromInt(@as(u32, @intCast(self.graph.switches.items.len)));
        try self.graph.switches.append(self.allocator, .{
            .expression = expression,
            .cases = .{ .start = case_start, .len = @intCast(local_cases.len) },
            .default_block = null,
            .exhaustive = local_cases.len == variants.len,
        });
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(expression)].source,
            .ty = try self.builtin(.Void),
            .content = .{ .switch_statement = switch_id },
        };
        self.stats.matches += 1;
        return .resolved;
    }
'''
text = text[:start] + new_function + text[end:]
control.write_text(text)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
anchor = '''                .resolve_choice_payload => |access| {
                    const value = graph.node(globalizer.globalNode(offsets[module_index], access.value));
                    const choice_ty = value.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty) or global_types.variants(graph, choice_ty) == null) continue;
                    const name = module.text(access.option_name);
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse continue;
                    if (hit.variant.payload_type != null) continue;
                    const source: @import("../primitives/schema.zig").SourceRef = .{
                        .file_index = offsets[module_index].file_base + access.source.file_index,
                        .offset = access.source.offset,
                    };
                    try diagnostics.add(
                        diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "choice variant '..{s}' has no payload",
                        .{name},
                    );
                    return true;
                },
                else => {},
'''
replacement = '''                .resolve_choice_payload => |access| {
                    const value = graph.node(globalizer.globalNode(offsets[module_index], access.value));
                    const choice_ty = value.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty) or global_types.variants(graph, choice_ty) == null) continue;
                    const name = module.text(access.option_name);
                    const hit = global_types.findVariant(graph, choice_ty, name) orelse continue;
                    if (hit.variant.payload_type != null) continue;
                    const source: @import("../primitives/schema.zig").SourceRef = .{
                        .file_index = offsets[module_index].file_base + access.source.file_index,
                        .offset = access.source.offset,
                    };
                    try diagnostics.add(
                        diagnosticLocation(graph, diagnostics, source),
                        .semantic,
                        "choice variant '..{s}' has no payload",
                        .{name},
                    );
                    return true;
                },
                .resolve_match => |match| {
                    const expression = graph.node(globalizer.globalNode(offsets[module_index], match.value));
                    const choice_ty = expression.ty orelse continue;
                    if (graph.isTypeUnresolved(choice_ty)) continue;
                    const variants = global_types.variants(graph, choice_ty) orelse {
                        var type_name = std.array_list.Managed(u8).init(allocator);
                        defer type_name.deinit();
                        try appendTypeName(&type_name, graph, choice_ty);
                        try diagnostics.add(
                            diagnosticLocation(graph, diagnostics, expression.source),
                            .semantic,
                            "match expects a choice value, found '{s}'",
                            .{type_name.items},
                        );
                        return true;
                    };
                    _ = variants;

                    var seen: std.ArrayList(global_sg.GlobalVariantId) = .empty;
                    defer seen.deinit(allocator);
                    for (module.semantic.node_refs.items[match.cases.start..][0..match.cases.len]) |local_case_node| {
                        const pending_id = switch (module.semantic.nodes.items[@intFromEnum(local_case_node)]) {
                            .pending => |id| id,
                            else => continue,
                        };
                        const case = switch (module.semantic.pending_operations.items[@intFromEnum(pending_id)]) {
                            .resolve_match_case => |item| item,
                            else => continue,
                        };
                        const option_ref = module.semantic.external_refs.items[@intFromEnum(case.option)];
                        const name = module.text(option_ref.name);
                        const source = globalSource(offsets[module_index], option_ref.source);
                        const hit = global_types.findVariant(graph, choice_ty, name) orelse {
                            var type_name = std.array_list.Managed(u8).init(allocator);
                            defer type_name.deinit();
                            try appendTypeName(&type_name, graph, choice_ty);
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice type '{s}' has no variant '..{s}'",
                                .{ type_name.items, name },
                            );
                            return true;
                        };
                        var duplicate = false;
                        for (seen.items) |previous| if (previous == hit.id) {
                            duplicate = true;
                            break;
                        };
                        if (duplicate) {
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice variant '..{s}' appears more than once in match",
                                .{name},
                            );
                            return true;
                        }
                        try seen.append(allocator, hit.id);

                        if (case.payload_binding != null and hit.variant.payload_type == null) {
                            const payload_source: @import("../primitives/schema.zig").SourceRef = .{
                                .file_index = source.file_index,
                                .offset = source.offset + @as(u32, @intCast(name.len + 1)),
                            };
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, payload_source),
                                .semantic,
                                "choice variant '..{s}' has no payload to bind",
                                .{name},
                            );
                            return true;
                        }
                        if (case.payload_binding == null and hit.variant.payload_type != null) {
                            try diagnostics.add(
                                diagnosticLocation(graph, diagnostics, source),
                                .semantic,
                                "choice variant '..{s}' carries a payload and match must bind it explicitly; use '..{s} _' to ignore it",
                                .{ name, name },
                            );
                            return true;
                        }
                    }
                },
                else => {},
'''
if text.count(anchor) != 1:
    raise RuntimeError(f"choice diagnostic anchor changed: {text.count(anchor)}")
semantizer.write_text(text.replace(anchor, replacement, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/types/06_choice_match "
    "-Dtest-filter=feature_tests/types/07_choice_match_payload_binding "
    "-Dtest-filter=feature_tests/types/12X_match_non_choice "
    "-Dtest-filter=feature_tests/types/13X_match_bind_payload_without_payload "
    "-Dtest-filter=feature_tests/types/28X_match_omit_payload_pattern\n"
)
Path(".git/semantic-refactor-message").write_text("Classify terminal match shape failures\n")

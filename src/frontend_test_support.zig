//! Compiler-facing entry point for fixture tests that run the frontend in-process.
pub const Environment = @import("4_semantics/frontend_test_support.zig").Environment;
pub const ExpectedDiagnostic = @import("4_semantics/frontend_test_support.zig").ExpectedDiagnostic;

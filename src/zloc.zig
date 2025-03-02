const std = @import("std");
const utils = @import("utils.zig");
pub const OpCode = @import("opcode.zig").OpCode;
pub const Value = @import("value.zig").Value;
pub const ValueArray = std.ArrayList(Value);
pub const Chunk = @import("chunk.zig").Chunk;
pub const VM = @import("vm.zig").VM;
pub const Compiler = @import("compiler.zig").Compiler;
pub const Scanner = @import("scanner.zig").Scanner;

pub fn printValue(value: Value) void {
    const stdout = utils.getStdoutWriter();
    stdout.print("{any}", .{value}) catch unreachable;
}

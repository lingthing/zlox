const std = @import("std");
const utils = @import("utils.zig");
pub const OpCode = @import("opcode.zig").OpCode;
pub const Value = @import("value.zig").Value;
pub const ValueArray = std.ArrayList(Value);
pub const Chunk = @import("chunk.zig").Chunk;

pub fn printValue(value: Value) void {
    const stdout = utils.getStdoutWriter();
    stdout.print("{any}", .{value}) catch unreachable;
}

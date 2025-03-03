const std = @import("std");
const utils = @import("utils.zig");
pub const OpCode = @import("opcode.zig").OpCode;
pub const Value = @import("value.zig").Value;
pub const ValueArray = std.ArrayList(Value);
pub const Chunk = @import("chunk.zig").Chunk;
pub const VM = @import("vm.zig").VM;
pub const Compiler = @import("compiler.zig").Compiler;
pub const Scanner = @import("scanner.zig").Scanner;
pub const Token = @import("scanner.zig").Token;
pub const TokenType = @import("scanner.zig").TokenType;

pub fn printValue(value: Value) void {
    const stdout = utils.getStdoutWriter();
    switch (value.type) {
        .val_bool => stdout.print("{}", .{value.asBool()}) catch unreachable,
        .val_nil => stdout.print("nil", .{}) catch unreachable,
        .val_number => stdout.print("{d}", .{value.asNumber()}) catch unreachable,
    }
}

const std = @import("std");
const zlox = @import("zlox.zig");
const OpCode = zlox.OpCode;
const Value = zlox.Value;
const VM = zlox.VM;

pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(u32),
    constants: zlox.ValueArray,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = std.ArrayList(u8).init(allocator),
            .lines = std.ArrayList(u32).init(allocator),
            .constants = zlox.ValueArray.init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.lines.deinit();
        self.constants.deinit();
    }

    pub fn write(self: *Chunk, byte: u8, line: u32) void {
        self.code.append(byte) catch @panic("OOM");
        self.lines.append(line) catch @panic("OOM");
    }

    pub fn addConstant(self: *Chunk, value: Value, vm: *VM) usize {
        vm.push(value);
        self.constants.append(value) catch @panic("OOM");
        _ = vm.pop();
        return self.constants.items.len - 1;
    }

    pub fn count(self: *Chunk) usize {
        return self.code.items.len;
    }

    pub fn getByte(self: *Chunk, index: usize) u8 {
        return self.code.items[index];
    }

    pub fn setByte(self: *Chunk, index: usize, value: u8) void {
        self.code.items[index] = value;
    }

    pub fn getLine(self: *Chunk, index: usize) u32 {
        return self.lines.items[index];
    }

    pub fn getConstant(self: *Chunk, index: usize) Value {
        return self.constants.items[index];
    }
};

const std = @import("std");
const zloc = @import("zloc.zig");
const OpCode = zloc.OpCode;
const Value = zloc.Value;

pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(u32),
    constants: zloc.ValueArray,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return Chunk{
            .code = std.ArrayList(u8).init(allocator),
            .lines = std.ArrayList(u32).init(allocator),
            .constants = zloc.ValueArray.init(allocator),
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

    pub fn addConstant(self: *Chunk, value: Value) usize {
        self.constants.append(value) catch @panic("OOM");
        return self.constants.items.len - 1;
    }

    pub fn count(self: *Chunk) usize {
        return self.code.items.len;
    }

    pub fn get(self: *Chunk, index: usize) u8 {
        return self.code.items[index];
    }

    pub fn set(self: *Chunk, index: usize, value: u8) void {
        self.code.items[index] = value;
    }
};

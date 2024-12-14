const std = @import("std");
const zloc = @import("zloc.zig");
pub const OpCode = zloc.OpCode;
pub const Value = zloc.Value;

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

    pub fn write(self: *Chunk, byte: anytype, line: u32) void {
        const byteType = @TypeOf(byte);
        if (byteType != u8 and byteType != OpCode) {
            @compileError(std.fmt.comptimePrint("Chunk.write() only accepts u8 or OpCode. Your type is {s}", .{@typeName(byteType)}));
        }

        if (byteType == u8) {
            self.code.append(byte) catch @panic("OOM");
        } else {
            self.code.append(@intFromEnum(byte)) catch @panic("OOM");
        }

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
};

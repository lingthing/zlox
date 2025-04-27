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
pub const ObjType = @import("object.zig").ObjType;
pub const Obj = @import("object.zig").Obj;
pub const ObjString = @import("object.zig").ObjString;
pub const ObjFunction = @import("object.zig").ObjFunction;
pub const ObjNative = @import("object.zig").ObjNative;
pub const ObjClosure = @import("object.zig").ObjClosure;
pub const NativeFn = @import("object.zig").NativeFn;
pub const ObjUpvalue = @import("object.zig").ObjUpvalue;
pub const Table = @import("table.zig").Table;

pub const printObject = @import("object.zig").printObject;
pub const copyString = @import("object.zig").copyString;
pub const takeString = @import("object.zig").takeString;
pub const allocateObject = @import("object.zig").allocateObject;
pub const allocateString = @import("object.zig").allocateString;
pub const freeObject = @import("object.zig").freeObject;
pub const newFunction = @import("object.zig").newFunction;
pub const newNative = @import("object.zig").newNative;
pub const newClosure = @import("object.zig").newClosure;
pub const newUpvalue = @import("object.zig").newUpvalue;
pub const collectGarbage = @import("gc.zig").collectGarbage;

pub fn printValue(value: Value) void {
    const stdout = utils.getStdoutWriter();
    switch (value.type) {
        .val_bool => stdout.print("{}", .{value.asBool()}) catch unreachable,
        .val_nil => stdout.print("nil", .{}) catch unreachable,
        .val_number => stdout.print("{d}", .{value.asNumber()}) catch unreachable,
        .val_obj => printObject(value),
    }
}

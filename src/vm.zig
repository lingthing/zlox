const std = @import("std");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const Value = zloc.Value;
const OpCode = zloc.OpCode;
const Compiler = zloc.Compiler;
const Obj = zloc.Obj;
const ObjString = zloc.ObjString;
const Table = zloc.Table;
const utils = @import("utils.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum {
    ok,
    compile_error,
    runtime_error,
};

pub const STACK_SIZE = 256;

pub const VM = struct {
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    ip: [*]u8,
    stack: []Value,
    stack_top: [*]Value,
    globals: Table,
    strings: Table,
    objects: ?*Obj,

    pub fn init(gpa: std.mem.Allocator) VM {
        var vm: VM = undefined;
        vm.gpa = gpa;
        vm.stack = gpa.alloc(Value, STACK_SIZE) catch unreachable;
        vm.resetStack();

        vm.objects = null;
        vm.globals = Table.init();
        vm.strings = Table.init();

        return vm;
    }

    pub fn deinit(vm: *VM) void {
        vm.globals.deinit();
        vm.strings.deinit();
        vm.freeObjects();
        vm.gpa.free(vm.stack);
    }

    fn freeObjects(vm: *VM) void {
        var object = vm.objects;
        while (object != null) {
            const next = object.?.next;
            zloc.freeObject(vm, object.?);
            object = next;
        }

        vm.objects = null;
    }

    pub fn interpret(vm: *VM, source: []const u8) InterpretResult {
        var chunk = Chunk.init(vm.gpa);
        defer chunk.deinit();

        var compiler = Compiler.init(vm);
        if (!compiler.compile(source, &chunk)) {
            return .compile_error;
        }

        vm.chunk = &chunk;
        vm.ip = chunk.code.items.ptr;

        return vm.run();
    }

    fn resetStack(vm: *VM) void {
        vm.stack_top = vm.stack.ptr;
    }

    fn runtimeError(vm: *VM, comptime fmt: []const u8, args: anytype) void {
        const stderr = utils.getStderrWriter();
        stderr.print(fmt, args) catch unreachable;
        stderr.print("\n", .{}) catch unreachable;

        const instruction = @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr) - 1;
        const line = vm.chunk.lines.items[instruction];
        stderr.print("[line {d}] in script\n", .{line}) catch unreachable;
        vm.resetStack();
    }

    fn readByte(vm: *VM) u8 {
        const byte = vm.ip[0];
        vm.ip += 1;

        return byte;
    }

    fn readConstant(vm: *VM) Value {
        return vm.chunk.constants.items[vm.readByte()];
    }

    fn readString(vm: *VM) *ObjString {
        return vm.readConstant().asString();
    }

    fn push(vm: *VM, value: Value) void {
        vm.stack_top[0] = value;
        vm.stack_top += 1;
    }

    fn pop(vm: *VM) Value {
        vm.stack_top -= 1;

        return vm.stack_top[0];
    }

    fn peek(vm: *VM, distance: usize) Value {
        return (vm.stack_top - 1 - distance)[0];
    }

    fn top(vm: *VM) *Value {
        return @ptrCast(vm.stack_top - 1);
    }

    fn run(vm: *VM) InterpretResult {
        const stdout = utils.getStdoutWriter();
        while (true) {
            if (debug.DEBUG_TRACE_EXECUTION) {
                stdout.print("          ", .{}) catch unreachable;
                var slot = vm.stack.ptr;
                while (slot != vm.stack_top) : (slot += 1) {
                    stdout.print("[ ", .{}) catch unreachable;
                    zloc.printValue(slot[0]);
                    stdout.print(" ]", .{}) catch unreachable;
                }
                stdout.print("\n", .{}) catch unreachable;
                _ = debug.disassembleInstruction(vm.chunk, @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr));
            }

            const instruction = OpCode.from(vm.readByte());
            switch (instruction) {
                .op_constant => {
                    const constant = vm.readConstant();
                    vm.push(constant);
                },
                .op_nil => {
                    vm.push(Value.initNil());
                },
                .op_true => {
                    vm.push(Value.initBool(true));
                },
                .op_false => {
                    vm.push(Value.initBool(false));
                },
                .op_pop => {
                    _ = vm.pop();
                },
                .op_get_global => {
                    const name = vm.readString();
                    var value: Value = undefined;
                    if (!vm.globals.get(name, &value)) {
                        vm.runtimeError("Undefined variable '{s}'.", .{name.chars});

                        return .runtime_error;
                    }
                    vm.push(value);
                },
                .op_define_global => {
                    const name = vm.readString();
                    _ = vm.globals.set(name, vm.peek(0));
                    _ = vm.pop();
                },
                .op_set_global => {
                    const name = vm.readString();
                    if (vm.globals.set(name, vm.peek(0))) {
                        _ = vm.globals.delete(name);
                        vm.runtimeError("Undefined variable '{s}'.", .{name.chars});

                        return .runtime_error;
                    }
                },
                .op_equal => {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(Value.initBool(Value.eql(a, b)));
                },
                .op_greater => {
                    if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                        vm.runtimeError("Operands must be numbers.", .{});
                        return .runtime_error;
                    }

                    const b = vm.pop().asNumber();
                    const a = vm.pop().asNumber();
                    vm.push(Value.initBool(a > b));
                },
                .op_less => {
                    if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                        vm.runtimeError("Operands must be numbers.", .{});
                        return .runtime_error;
                    }

                    const b = vm.pop().asNumber();
                    const a = vm.pop().asNumber();
                    vm.push(Value.initBool(a < b));
                },
                .op_add => {
                    if (vm.peek(0).isString() and vm.peek(1).isString()) {
                        const b = vm.pop().asRawString();
                        const a = vm.pop().asRawString();

                        const length = a.len + b.len;
                        var chars = vm.gpa.alloc(u8, length) catch {
                            // TODO: handle memory not enough
                            unreachable;
                        };
                        std.mem.copyForwards(u8, chars[0..a.len], a);
                        std.mem.copyForwards(u8, chars[a.len..], b);
                        vm.push(Value.initObj(zloc.takeString(vm, chars).?));
                    } else if (vm.peek(0).isNumber() and vm.peek(1).isNumber()) {
                        const b = vm.pop().asNumber();
                        const a = vm.pop().asNumber();
                        vm.push(Value.initNumber(a + b));
                    } else {
                        vm.runtimeError("Operands must be two numbers or two strings.", .{});
                        return .runtime_error;
                    }
                },
                .op_subtract => {
                    if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                        vm.runtimeError("Operands must be numbers.", .{});
                        return .runtime_error;
                    }

                    const b = vm.pop().asNumber();
                    const a = vm.pop().asNumber();
                    vm.push(Value.initNumber(a - b));
                },
                .op_multiply => {
                    if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                        vm.runtimeError("Operands must be numbers.", .{});
                        return .runtime_error;
                    }

                    const b = vm.pop().asNumber();
                    const a = vm.pop().asNumber();
                    vm.push(Value.initNumber(a * b));
                },
                .op_divide => {
                    if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                        vm.runtimeError("Operands must be numbers.", .{});
                        return .runtime_error;
                    }

                    const b = vm.pop().asNumber();
                    const a = vm.pop().asNumber();
                    vm.push(Value.initNumber(a / b));
                },
                .op_not => {
                    vm.push(Value.initBool(isFalsey(vm.pop())));
                },
                .op_negate => {
                    if (!vm.peek(0).isNumber()) {
                        vm.runtimeError("Operand must be a number.", .{});
                        return .runtime_error;
                    }

                    // naive way
                    vm.push(Value.initNumber(-vm.pop().asNumber()));

                    // smart way
                    // const ptr = vm.top();
                    // ptr.* = -ptr.*;
                },
                .op_print => {
                    zloc.printValue(vm.pop());
                    stdout.print("\n", .{}) catch unreachable;
                },
                .op_return => {
                    return .ok;
                },
            }
        }
    }
};

fn isFalsey(value: Value) bool {
    return switch (value.type) {
        .val_nil => true,
        .val_bool => !value.asBool(),
        else => false,
    };
}

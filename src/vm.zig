const std = @import("std");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const Value = zloc.Value;
const OpCode = zloc.OpCode;
const Compiler = zloc.Compiler;
const Obj = zloc.Obj;
const ObjString = zloc.ObjString;
const ObjFunction = zloc.ObjFunction;
const ObjNative = zloc.ObjNative;
const NativeFn = zloc.NativeFn;
const ObjClosure = zloc.ObjClosure;
const ObjUpvalue = zloc.ObjUpvalue;
const Table = zloc.Table;
const MemoryManager = @import("memory.zig").MemoryManager;
const utils = @import("utils.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum {
    ok,
    compile_error,
    runtime_error,
};

pub const FRAMES_MAX = 64;
pub const STACK_SIZE = FRAMES_MAX * 256;

const CallFrame = struct {
    closure: *ObjClosure,
    ip: [*]u8,
    slots: [*]Value,

    fn readByte(frame: *CallFrame) u8 {
        const byte = frame.ip[0];
        frame.ip += 1;

        return byte;
    }

    fn readShort(frame: *CallFrame) u16 {
        const byte1 = frame.ip[0];
        const byte2 = frame.ip[1];
        frame.ip += 2;

        return @as(u16, @as(u16, byte1) << 8 | byte2);
    }

    fn readConstant(frame: *CallFrame) Value {
        return frame.closure.function.chunk.getConstant(frame.readByte());
    }

    fn readString(frame: *CallFrame) *ObjString {
        return frame.readConstant().asString();
    }
};

fn clockNative(args: []Value) Value {
    _ = args;

    return Value.initNumber(@floatFromInt(std.time.milliTimestamp()));
}

fn exitNative(args: []Value) Value {
    _ = args;

    std.process.exit(0);
}

fn fib(n: f64) f64 {
    if (n <= 0) return 0;
    if (n <= 2) return 1;

    return fib(n - 1) + fib(n - 2);
}

fn fibNative(args: []Value) Value {
    return Value.initNumber(fib(args[0].asNumber()));
}

pub const VM = struct {
    gpa: std.mem.Allocator, // raw
    allocator: std.mem.Allocator, // normal
    memory_manager: *MemoryManager,
    frames: [FRAMES_MAX]CallFrame,
    frame_count: usize,
    stack: []Value,
    stack_top: [*]Value,
    globals: Table,
    strings: Table,
    open_upvalues: ?*ObjUpvalue,
    objects: ?*Obj,

    bytes_allocated: usize,
    next_gc: usize,
    gray_stack: std.ArrayList(*Obj),

    pub fn init(gpa: std.mem.Allocator) *VM {
        var vm: *VM = gpa.create(VM) catch unreachable;
        vm.gpa = gpa;
        vm.memory_manager = gpa.create(MemoryManager) catch unreachable;
        vm.memory_manager.* = MemoryManager.init(vm, gpa);
        vm.allocator = vm.memory_manager.allocator();

        vm.stack = gpa.alloc(Value, STACK_SIZE) catch unreachable;
        vm.resetStack();

        vm.objects = null;
        vm.globals = Table.init();
        vm.strings = Table.init();

        vm.bytes_allocated = 0;
        vm.next_gc = 1024 * 1024;
        vm.gray_stack = std.ArrayList(*Obj).init(gpa);

        vm.defineNative("clock", clockNative);
        vm.defineNative("exit", exitNative);
        vm.defineNative("fib", fibNative);

        return vm;
    }

    pub fn deinit(vm: *VM) void {
        vm.globals.deinit();
        vm.strings.deinit();
        vm.freeObjects();
        vm.gpa.free(vm.stack);

        vm.memory_manager.deinit();
        vm.gpa.destroy(vm.memory_manager);

        vm.gray_stack.deinit();
        vm.gpa.destroy(vm);
    }

    fn freeObjects(vm: *VM) void {
        var it = vm.objects;
        while (it) |object| {
            const next = object.next;
            zloc.freeObject(vm, object);
            it = next;
        }

        vm.objects = null;
    }

    pub fn interpret(vm: *VM, source: []const u8) InterpretResult {
        var compiler = Compiler.init(vm, .type_script, null);
        Compiler.current = &compiler;
        const function = compiler.compile(source) orelse return .compile_error;

        vm.resetStack();
        vm.push(Value.initObj(function));
        const closure = zloc.newClosure(vm, function).?;
        _ = vm.pop();
        vm.push(Value.initObj(closure));
        _ = vm.call(closure, 0);

        return vm.run();
    }

    fn resetStack(vm: *VM) void {
        vm.stack_top = vm.stack.ptr;
        vm.frame_count = 0;
        vm.open_upvalues = null;
    }

    fn runtimeError(vm: *VM, comptime fmt: []const u8, args: anytype) void {
        const stderr = utils.getStderrWriter();
        stderr.print(fmt, args) catch unreachable;
        stderr.print("\n", .{}) catch unreachable;

        var i: usize = vm.frame_count;
        while (i > 0) {
            i -= 1;
            const frame = &vm.frames[i];
            const function = frame.closure.function;
            const instruction = @intFromPtr(frame.ip) - @intFromPtr(function.chunk.code.items.ptr) - 1;
            const line = function.chunk.getLine(instruction);
            stderr.print("[line {d}] in ", .{line}) catch unreachable;
            if (function.name) |name| {
                stderr.print("{s}()", .{name.chars}) catch unreachable;
            } else {
                stderr.print("script", .{}) catch unreachable;
            }
            stderr.print("\n", .{}) catch unreachable;
        }

        vm.resetStack();
    }

    fn defineNative(vm: *VM, name: []const u8, function: NativeFn) void {
        vm.push(Value.initObj(zloc.copyString(vm, name).?));
        vm.push(Value.initObj(zloc.newNative(vm, function).?));
        _ = vm.globals.set(vm.stack[0].asString(), vm.stack[1]);
        _ = vm.pop();
        _ = vm.pop();
    }

    pub fn push(vm: *VM, value: Value) void {
        vm.stack_top[0] = value;
        vm.stack_top += 1;
    }

    pub fn pop(vm: *VM) Value {
        vm.stack_top -= 1;

        return vm.stack_top[0];
    }

    pub fn peek(vm: *VM, distance: usize) Value {
        return (vm.stack_top - 1 - distance)[0];
    }

    pub fn top(vm: *VM) *Value {
        return @ptrCast(vm.stack_top - 1);
    }

    fn callValue(vm: *VM, callee: Value, arg_count: u8) bool {
        if (callee.isObj()) {
            switch (callee.objType()) {
                .obj_closure => {
                    return vm.call(callee.asClosure(), arg_count);
                },
                .obj_native => {
                    const native = callee.asNative();
                    const result = native.function((vm.stack_top - arg_count)[0..arg_count]);
                    vm.stack_top -= arg_count + 1;
                    vm.push(result);

                    return true;
                },
                else => {
                    // Non-callable object type
                },
            }
        }

        vm.runtimeError("Can only call functions or classes.", .{});
        return false;
    }

    fn call(vm: *VM, closure: *ObjClosure, arg_count: u8) bool {
        if (arg_count != closure.function.arity) {
            vm.runtimeError("Expected {d} argument(s), but got {d}.", .{ closure.function.arity, arg_count });

            return false;
        }

        if (vm.frame_count == FRAMES_MAX) {
            vm.runtimeError("Stack overflow.", .{});

            return false;
        }

        var frame = &vm.frames[vm.frame_count];
        vm.frame_count += 1;
        frame.closure = closure;
        frame.ip = closure.function.chunk.code.items.ptr;
        frame.slots = vm.stack_top - arg_count - 1;

        return true;
    }

    fn captureUpvalue(vm: *VM, local: *Value) *ObjUpvalue {
        var prev_upvalue: ?*ObjUpvalue = null;
        var upvalue = vm.open_upvalues;
        while (upvalue != null and @intFromPtr(upvalue.?.location) > @intFromPtr(local)) {
            prev_upvalue = upvalue;
            upvalue = upvalue.?.next;
        }

        if (upvalue != null and upvalue.?.location == local) {
            return upvalue.?;
        }

        const createdUpvalue = zloc.newUpvalue(vm, local).?;
        createdUpvalue.next = upvalue;
        if (prev_upvalue == null) {
            vm.open_upvalues = createdUpvalue;
        } else {
            prev_upvalue.?.next = createdUpvalue;
        }

        return createdUpvalue;
    }

    fn closeUpvalues(vm: *VM, last: *Value) void {
        while (vm.open_upvalues != null and
            @intFromPtr(vm.open_upvalues.?.location) >= @intFromPtr(last))
        {
            const upvalue = vm.open_upvalues;
            upvalue.?.closed = upvalue.?.location.*;
            upvalue.?.location = &upvalue.?.closed;
            vm.open_upvalues = upvalue.?.next;
        }
    }

    fn run(vm: *VM) InterpretResult {
        const stdout = utils.getStdoutWriter();
        var frame = &vm.frames[vm.frame_count - 1];

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
                _ = debug.disassembleInstruction(
                    &frame.closure.function.chunk,
                    @intFromPtr(frame.ip) - @intFromPtr(frame.closure.function.chunk.code.items.ptr),
                );
            }

            const instruction = OpCode.from(frame.readByte());
            switch (instruction) {
                .op_constant => {
                    const constant = frame.readConstant();
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
                .op_get_local => {
                    const slot = frame.readByte();
                    vm.push(frame.slots[slot]);
                },
                .op_set_local => {
                    const slot = frame.readByte();
                    frame.slots[slot] = vm.peek(0);
                },
                .op_get_global => {
                    const name = frame.readString();
                    var value: Value = undefined;
                    if (!vm.globals.get(name, &value)) {
                        vm.runtimeError("Undefined variable '{s}'.", .{name.chars});

                        return .runtime_error;
                    }
                    vm.push(value);
                },
                .op_define_global => {
                    const name = frame.readString();
                    _ = vm.globals.set(name, vm.peek(0));
                    _ = vm.pop();
                },
                .op_set_global => {
                    const name = frame.readString();
                    if (vm.globals.set(name, vm.peek(0))) {
                        _ = vm.globals.delete(name);
                        vm.runtimeError("Undefined variable '{s}'.", .{name.chars});

                        return .runtime_error;
                    }
                },
                .op_get_upvalue => {
                    const slot = frame.readByte();
                    vm.push(frame.closure.upvalues[slot].?.location.*);
                },
                .op_set_upvalue => {
                    const slot = frame.readByte();
                    frame.closure.upvalues[slot].?.location.* = vm.peek(0);
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
                        const b = vm.peek(0).asRawString();
                        const a = vm.peek(1).asRawString();

                        const length = a.len + b.len;
                        var chars = vm.allocator.alloc(u8, length) catch {
                            // TODO: handle memory not enough
                            @panic("OOM");
                        };
                        std.mem.copyForwards(u8, chars[0..a.len], a);
                        std.mem.copyForwards(u8, chars[a.len..], b);

                        _ = vm.pop(); // pop b
                        _ = vm.pop(); // pop a
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
                .op_jump => {
                    const offset = frame.readShort();
                    frame.ip += offset;
                },
                .op_jump_if_false => {
                    const offset = frame.readShort();
                    if (isFalsey(vm.peek(0))) {
                        frame.ip += offset;
                    }
                },
                .op_loop => {
                    const offset = frame.readShort();
                    frame.ip -= offset;
                },
                .op_call => {
                    const arg_count = frame.readByte();
                    if (!vm.callValue(vm.peek(arg_count), arg_count)) {
                        return .runtime_error;
                    }
                    frame = &vm.frames[vm.frame_count - 1];
                },
                .op_closure => {
                    const function = frame.readConstant().asFunction();
                    const closure = zloc.newClosure(vm, function).?;
                    vm.push(Value.initObj(closure));
                    for (0..closure.upvalue_count) |i| {
                        const is_local = frame.readByte() == 1;
                        const index = frame.readByte();
                        if (is_local) {
                            closure.upvalues[i] = vm.captureUpvalue(&frame.slots[index]);
                        } else {
                            closure.upvalues[i] = frame.closure.upvalues[index];
                        }
                    }
                },
                .op_close_upvalue => {
                    vm.closeUpvalues(&(vm.stack_top - 1)[0]);
                    _ = vm.pop();
                },
                .op_return => {
                    const result = vm.pop();
                    vm.closeUpvalues(&frame.slots[0]);
                    vm.frame_count -= 1;
                    if (vm.frame_count == 0) {
                        _ = vm.pop();

                        return .ok;
                    }

                    vm.stack_top = frame.slots;
                    vm.push(result);
                    frame = &vm.frames[vm.frame_count - 1];
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

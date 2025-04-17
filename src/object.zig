pub const ObjType = enum {
    obj_closure,
    obj_function,
    obj_native,
    obj_string,
    obj_upvalue,
};

pub const Obj = struct {
    type: ObjType,
    next: ?*Obj = null,

    pub fn asClosure(self: *Obj) *ObjClosure {
        return @as(*ObjClosure, @ptrCast(self));
    }

    pub fn asFunction(self: *Obj) *ObjFunction {
        return @as(*ObjFunction, @ptrCast(self));
    }

    pub fn asNative(self: *Obj) *ObjNative {
        return @as(*ObjNative, @ptrCast(self));
    }

    pub fn asString(self: *Obj) *ObjString {
        return @as(*ObjString, @ptrCast(self));
    }

    pub fn asUpvalue(self: *Obj) *ObjUpvalue {
        return @as(*ObjUpvalue, @ptrCast(self));
    }
};

pub const ObjClosure = struct {
    obj: Obj,
    function: *ObjFunction,
    upvalues: [*]?*ObjUpvalue,
    upvalue_count: usize,

    pub fn asObj(self: *ObjClosure) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjFunction = struct {
    obj: Obj,
    arity: usize,
    upvalue_count: usize,
    chunk: Chunk,
    name: ?*ObjString,

    pub fn asObj(self: *ObjFunction) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const NativeFn = *const fn (args: []Value) Value;

pub const ObjNative = struct {
    obj: Obj,
    function: NativeFn,

    pub fn asObj(self: *ObjNative) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjString = struct {
    obj: Obj,
    chars: []u8,
    hash: u32,

    pub fn asObj(self: *ObjString) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjUpvalue = struct {
    obj: Obj,
    location: *Value,
    closed: Value,
    next: ?*ObjUpvalue,

    pub fn asObj(self: *ObjUpvalue) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub fn copyString(vm: *VM, chars: []const u8) ?*ObjString {
    const hash = hashString(chars);
    const interned = vm.strings.findString(chars, hash);
    if (interned != null) {
        return interned;
    }

    const new_chars = vm.gpa.dupe(u8, chars) catch return null;

    return allocateString(vm, new_chars, hash);
}

pub fn takeString(vm: *VM, chars: []const u8) ?*ObjString {
    const hash = hashString(chars);
    const interned = vm.strings.findString(chars, hash);
    if (interned != null) {
        vm.gpa.free(chars);

        return interned;
    }

    return allocateString(vm, chars, hash);
}

pub fn printObject(value: Value) void {
    const stdout = utils.getStdoutWriter();

    switch (value.objType()) {
        .obj_closure => {
            printFunction(value.asClosure().function);
        },
        .obj_function => {
            printFunction(value.asFunction());
        },
        .obj_native => {
            stdout.print("<native fn>", .{}) catch unreachable;
        },
        .obj_string => {
            stdout.print("{s}", .{value.asRawString()}) catch unreachable;
        },
        .obj_upvalue => {
            stdout.print("upvalue", .{}) catch unreachable;
        },
    }
}

fn printFunction(function: *ObjFunction) void {
    const stdout = utils.getStdoutWriter();
    if (function.name == null) {
        stdout.print("<script>", .{}) catch unreachable;
        return;
    }

    stdout.print("<fn {s}>", .{function.name.?.chars}) catch unreachable;
}

pub fn allocateObject(vm: *VM, comptime obj_type: ObjType) ?*Obj {
    const unknown = vm.gpa.create(comptime blk: {
        switch (obj_type) {
            .obj_closure => break :blk ObjClosure,
            .obj_function => break :blk ObjFunction,
            .obj_native => break :blk ObjNative,
            .obj_string => break :blk ObjString,
            .obj_upvalue => break :blk ObjUpvalue,
        }
    }) catch return null;

    var object = unknown.asObj();
    object.type = obj_type;

    object.next = vm.objects;
    vm.objects = object;

    return object;
}

pub fn allocateString(vm: *VM, chars: []const u8, hash: u32) ?*ObjString {
    var object = allocateObject(vm, .obj_string) orelse return null;
    var string = object.asString();
    string.chars = @constCast(chars);
    string.hash = hash;

    _ = vm.strings.set(string, Value.initNil());

    return string;
}

pub fn freeObject(vm: *VM, obj: *Obj) void {
    switch (obj.type) {
        .obj_closure => {
            const closure = obj.asClosure();
            vm.gpa.free(closure.upvalues[0..closure.upvalue_count]);
            vm.gpa.destroy(closure);
        },
        .obj_function => {
            const function = obj.asFunction();
            function.chunk.deinit();
            vm.gpa.destroy(function);
        },
        .obj_native => {
            const native = obj.asNative();
            vm.gpa.destroy(native);
        },
        .obj_string => {
            const string = obj.asString();
            vm.gpa.free(string.chars);
            vm.gpa.destroy(string);
        },
        .obj_upvalue => {
            const upvalue = obj.asUpvalue();
            vm.gpa.destroy(upvalue);
        },
    }
}

fn hashString(keys: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (keys) |c| {
        hash ^= c;
        hash = @as(u32, @truncate(@as(u64, hash) * 16777619));
    }

    return hash;
}

pub fn newFunction(vm: *VM) ?*ObjFunction {
    const object = allocateObject(vm, .obj_function) orelse return null;
    const function = object.asFunction();
    function.arity = 0;
    function.upvalue_count = 0;
    function.chunk = Chunk.init(vm.gpa);
    function.name = null;

    return function;
}

pub fn newNative(vm: *VM, function: NativeFn) ?*ObjNative {
    const object = allocateObject(vm, .obj_native) orelse return null;
    const native = object.asNative();
    native.function = function;

    return native;
}

pub fn newClosure(vm: *VM, function: *ObjFunction) ?*ObjClosure {
    var upvalues = vm.gpa.alloc(?*ObjUpvalue, function.upvalue_count) catch return null;
    for (0..function.upvalue_count) |i| {
        upvalues[i] = null;
    }

    const object: *Obj = allocateObject(vm, .obj_closure) orelse {
        vm.gpa.free(upvalues);

        return null;
    };
    const closure = object.asClosure();
    closure.function = function;
    closure.upvalues = upvalues.ptr;
    closure.upvalue_count = function.upvalue_count;

    return closure;
}

pub fn newUpvalue(vm: *VM, slot: *Value) ?*ObjUpvalue {
    const object = allocateObject(vm, .obj_upvalue) orelse return null;
    const upvalue = object.asUpvalue();
    upvalue.location = slot;
    upvalue.closed = Value.initNil();
    upvalue.next = null;

    return upvalue;
}

const std = @import("std");
const zloc = @import("zloc.zig");
const utils = @import("utils.zig");
const Value = zloc.Value;
const Chunk = zloc.Chunk;
const VM = zloc.VM;

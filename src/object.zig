pub const ObjType = enum {
    obj_function,
    obj_native,
    obj_string,
};

pub const Obj = struct {
    type: ObjType,
    next: ?*Obj = null,

    pub fn asFunction(self: *Obj) *ObjFunction {
        return @as(*ObjFunction, @ptrCast(self));
    }

    pub fn asNative(self: *Obj) *ObjNative {
        return @as(*ObjNative, @ptrCast(self));
    }

    pub fn asString(self: *Obj) *ObjString {
        return @as(*ObjString, @ptrCast(self));
    }
};

pub const ObjFunction = struct {
    obj: Obj,
    arity: usize,
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
        .obj_function => {
            printFunction(value.asFunction());
        },
        .obj_native => {
            stdout.print("<native fn>", .{}) catch unreachable;
        },
        .obj_string => {
            stdout.print("{s}", .{value.asRawString()}) catch unreachable;
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
            .obj_function => break :blk ObjFunction,
            .obj_native => break :blk ObjNative,
            .obj_string => break :blk ObjString,
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

const std = @import("std");
const zloc = @import("zloc.zig");
const utils = @import("utils.zig");
const Value = zloc.Value;
const Chunk = zloc.Chunk;
const VM = zloc.VM;

pub const ValueType = enum {
    val_nil,
    val_bool,
    val_number,
    val_obj,
};

pub const Value = struct {
    type: ValueType,
    as: union {
        boolean: bool,
        number: f64,
        obj: *Obj,
    },

    pub fn initBool(value: bool) Value {
        return .{
            .type = .val_bool,
            .as = .{ .boolean = value },
        };
    }

    pub fn initNil() Value {
        return .{
            .type = .val_nil,
            .as = .{ .number = 0 },
        };
    }

    pub fn initNumber(value: f64) Value {
        return .{
            .type = .val_number,
            .as = .{ .number = value },
        };
    }

    pub fn initObj(value: anytype) Value {
        const typeInfo = @typeInfo(@TypeOf(value));
        if (typeInfo != .Pointer) {
            @compileError("Value.initObj() expects a pointer");
        }
        if (typeInfo.Pointer.size != .One) {
            @compileError("Value.initObj() only supports a one pointer");
        }
        if (@typeInfo(typeInfo.Pointer.child).Struct.fields[0].type != Obj and
            @TypeOf(value) != *Obj)
        {
            @compileError("Value.initObj() expects a pointer to struct with Obj as first field or a pointer to Obj");
        }

        return .{
            .type = .val_obj,
            .as = .{ .obj = @as(*Obj, @ptrCast(value)) },
        };
    }

    pub fn isBool(value: Value) bool {
        return value.type == .val_bool;
    }

    pub fn isNil(value: Value) bool {
        return value.type == .val_nil;
    }

    pub fn isNumber(value: Value) bool {
        return value.type == .val_number;
    }

    pub fn isObj(value: Value) bool {
        return value.type == .val_obj;
    }

    pub fn isObjType(value: Value, obj_type: ObjType) bool {
        return value.isObj() and value.objType() == obj_type;
    }

    pub fn isClass(value: Value) bool {
        return value.isObjType(.obj_class);
    }

    pub fn isInstance(value: Value) bool {
        return value.isObjType(.obj_instance);
    }

    pub fn isBoundMethod(value: Value) bool {
        return value.isObjType(.obj_bound_method);
    }

    pub fn isClosure(value: Value) bool {
        return value.isObjType(.obj_closure);
    }

    pub fn isFunction(value: Value) bool {
        return value.isObjType(.obj_function);
    }

    pub fn isNative(value: Value) bool {
        return value.isObjType(.obj_native);
    }

    pub fn isString(value: Value) bool {
        return value.isObjType(.obj_string);
    }

    pub fn asBool(value: Value) bool {
        return value.as.boolean;
    }

    pub fn asNumber(value: Value) f64 {
        return value.as.number;
    }

    pub fn asObj(value: Value) *Obj {
        return value.as.obj;
    }

    pub fn asClass(value: Value) *ObjClass {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asInstance(value: Value) *ObjInstance {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asBoundMethod(value: Value) *ObjBoundMethod {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asClosure(value: Value) *ObjClosure {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asFunction(value: Value) *ObjFunction {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asNative(value: Value) *ObjNative {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asString(value: Value) *ObjString {
        return @alignCast(@ptrCast(value.as.obj));
    }

    pub fn asRawString(value: Value) []u8 {
        return value.asString().chars;
    }

    pub fn objType(value: Value) ObjType {
        return value.as.obj.type;
    }

    pub fn eql(a: Value, b: Value) bool {
        if (a.type != b.type) return false;

        switch (a.type) {
            .val_bool => return a.asBool() == b.asBool(),
            .val_nil => return true,
            .val_number => return a.asNumber() == b.asNumber(),
            .val_obj => return a.asObj() == b.asObj(),
        }
    }
};

const std = @import("std");
const zloc = @import("zloc.zig");
const ObjType = zloc.ObjType;
const Obj = zloc.Obj;
const ObjString = zloc.ObjString;
const ObjFunction = zloc.ObjFunction;
const ObjNative = zloc.ObjNative;
const ObjClosure = zloc.ObjClosure;
const ObjClass = zloc.ObjClass;
const ObjInstance = zloc.ObjInstance;
const ObjBoundMethod = zloc.ObjBoundMethod;

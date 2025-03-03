pub const ValueType = enum {
    val_bool,
    val_nil,
    val_number,
};

pub const Value = struct {
    type: ValueType,
    as: union {
        boolean: bool,
        number: f64,
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

    pub fn isBool(value: Value) bool {
        return value.type == .val_bool;
    }

    pub fn isNil(value: Value) bool {
        return value.type == .val_nil;
    }

    pub fn isNumber(value: Value) bool {
        return value.type == .val_number;
    }

    pub fn asBool(value: Value) bool {
        return value.as.boolean;
    }

    pub fn asNumber(value: Value) f64 {
        return value.as.number;
    }

    pub fn eql(a: Value, b: Value) bool {
        if (a.type != b.type) return false;

        switch (a.type) {
            .val_bool => return a.asBool() == b.asBool(),
            .val_nil => return true,
            .val_number => return a.asNumber() == b.asNumber(),
        }
    }
};

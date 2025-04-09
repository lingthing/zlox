pub const OpCode = enum(u8) {
    op_constant,
    op_nil,
    op_true,
    op_false,
    op_pop,
    op_get_local,
    op_set_local,
    op_get_global,
    op_define_global,
    op_set_global,
    op_equal,
    op_greater,
    op_less,
    op_add,
    op_subtract,
    op_multiply,
    op_divide,
    op_not,
    op_negate,
    op_print,
    op_return,

    pub inline fn from(byte: u8) OpCode {
        return @enumFromInt(byte);
    }

    pub inline fn @"u8"(self: OpCode) u8 {
        return @intFromEnum(self);
    }

    pub fn toString(self: OpCode) []const u8 {
        return switch (self) {
            .op_constant => "OP_CONSTANT",
            .op_nil => "OP_NIL",
            .op_true => "OP_TRUE",
            .op_false => "OP_FALSE",
            .op_pop => "OP_POP",
            .op_get_local => "OP_GET_LOCAL",
            .op_set_local => "OP_SET_LOCAL",
            .op_get_global => "OP_GET_GLOBAL",
            .op_define_global => "OP_DEFINE_GLOBAL",
            .op_set_global => "OP_SET_GLOBAL",
            .op_equal => "OP_EQUAL",
            .op_greater => "OP_GREATER",
            .op_less => "OP_LESS",
            .op_add => "OP_ADD",
            .op_subtract => "OP_SUBTRACT",
            .op_multiply => "OP_MULTIPLY",
            .op_divide => "OP_DIVIDE",
            .op_not => "OP_NOT",
            .op_negate => "OP_NEGATE",
            .op_print => "OP_PRINT",
            .op_return => "OP_RETURN",
        };
    }
};

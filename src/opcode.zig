pub const OpCode = enum(u8) {
    op_constant,
    op_add,
    op_subtract,
    op_multiply,
    op_divide,
    op_negate,
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
            .op_add => "OP_ADD",
            .op_subtract => "OP_SUBTRACT",
            .op_multiply => "OP_MULTIPLY",
            .op_divide => "OP_DIVIDE",
            .op_negate => "OP_NEGATE",
            .op_return => "OP_RETURN",
        };
    }
};

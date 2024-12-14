pub const OpCode = enum(u8) {
    op_constant,
    op_return,

    pub fn toString(self: OpCode) []const u8 {
        return switch (self) {
            .op_constant => "OP_CONSTANT",
            .op_return => "OP_RETURN",
        };
    }
};

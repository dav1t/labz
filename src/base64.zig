const std = @import("std");

pub const Base64 = struct {
    _table: *const [64]u8,

    pub fn init() Base64 {
        const upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const lower = "abcdefghijklmnopqrstuvwxyz";
        const number_symb = "0123456789+/";

        return Base64{
            ._table = upper ++ lower ++ number_symb,
        };
    }

    pub fn char_at(self: Base64, index: usize) u8 {
        return self._table[index];
    }

    fn _char_index(self: Base64, char: u8) u8 {
        if (char == '=') return 64;

        for (self._table, 0..) |c, i| {
            if (c == char) {
                return @truncate(i);
            }
        }

        return 63;
    }

    pub fn encode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) return "";

        const output_size = try _calc_encode_length(input);
        var output = try allocator.alloc(u8, output_size);
        var i: u64 = 0;
        var iout: u64 = 0;

        while (i < input.len) : (i += 3) {
            if (i + 3 > input.len) {
                const remaining = input.len - i;
                var temp: u24 = 0;
                if (remaining >= 1) temp |= @as(u24, input[i]) << 16;
                if (remaining >= 2) temp |= @as(u24, input[i + 1]) << 8;
                output[iout + 0] = self.char_at(@truncate((temp >> 18) & 0x3F));
                output[iout + 1] = self.char_at(@truncate((temp >> 12) & 0x3F));
                if (remaining == 1) {
                    output[iout + 2] = '=';
                    output[iout + 3] = '=';
                } else {
                    output[iout + 2] = self.char_at(@truncate((temp >> 6) & 0x3F));
                    output[iout + 3] = '=';
                }
                iout += 4;
            } else {
                const temp: u24 = (@as(u24, input[i]) << 16) |
                    (@as(u24, input[i + 1]) << 8) |
                    @as(u24, input[i + 2]);
                output[iout + 0] = self.char_at(@truncate((temp >> 18) & 0x3F));
                output[iout + 1] = self.char_at(@truncate((temp >> 12) & 0x3F));
                output[iout + 2] = self.char_at(@truncate((temp >> 6) & 0x3F));
                output[iout + 3] = self.char_at(@truncate(temp & 0x3F));
                iout += 4;
            }
        }

        return output;
    }

    pub fn decode(self: Base64, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len == 0) {
            return "";
        }
        const n_output = try _calc_decode_length(input);
        var output = try allocator.alloc(u8, n_output);
        var count: u8 = 0;
        var iout: u64 = 0;
        var buf = [4]u8{ 0, 0, 0, 0 };

        for (0..input.len) |i| {
            buf[count] = self._char_index(input[i]);
            count += 1;
            if (count == 4) {
                output[iout] = (buf[0] << 2) + (buf[1] >> 4);
                if (buf[2] != 64) {
                    output[iout + 1] = (buf[1] << 4) + (buf[2] >> 2);
                }
                if (buf[3] != 64) {
                    output[iout + 2] = (buf[2] << 6) + buf[3];
                }
                iout += 3;
                count = 0;
            }
        }

        return output;
    }
};

fn _calc_encode_length(input: []const u8) !usize {
    if (input.len < 3) return 4;

    const n_groups: usize = try std.math.divCeil(usize, input.len, 3);
    return n_groups * 4;
}

fn _calc_decode_length(input: []const u8) !usize {
    if (input.len < 4) return 3;

    const n_groups: usize = try std.math.divCeil(usize, input.len, 4);
    var multiple_groups: usize = n_groups * 3;
    var i: usize = input.len - 1;
    while (i > 0) : (i -= 1) {
        if (input[i] == '=') {
            multiple_groups -= 1;
        } else break;
    }

    return multiple_groups;
}

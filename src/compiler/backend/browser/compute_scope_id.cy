// Operation: exact source-path bytes -> Zig-compatible Wyhash scope ID.
// Matches Zig std.hash.Wyhash (one-shot), including the 48-byte block boundary.
struct Product {
    low: u64;
    high: u64;
}
fn product(a: u64, b: u64): Product {
    const mask: u64 = 0xffffffff;
    const lo_a = a & mask;
    const hi_a = a >> 32;
    const lo_b = b & mask;
    const hi_b = b >> 32;
    const base = lo_a * lo_b;
    const first = hi_a * lo_b + (base >> 32);
    const middle = lo_a * hi_b + (first & mask);
    return {
        low: ((middle & mask) << 32) | (base & mask),
        high: hi_a * hi_b + (first >> 32) + (middle >> 32)
    };
}
fn mix(a: u64, b: u64): u64 {
    const value = product(a, b);
    return value.low ^ value.high;
}
fn read(bytes: []const u8, start: usize, count: usize): u64 {
    var value: u64 = 0;
    var i: usize = 0;
    while i < count {
        value = value | ((bytes[start + i] as u64) << (i * 8));
        i = i + 1;
    }
    return value;
}
pub fn hash(bytes: []const u8, seed: u64): u64 {
    const s0: u64 = 0xa0761d6478bd642f;
    const s1: u64 = 0xe7037ed1a0b428db;
    const s2: u64 = 0x8ebc6af09c88c6e3;
    const s3: u64 = 0x589965cc75374cc3;
    var state = seed ^ mix(seed ^ s0, s1);
    var state1 = state;
    var state2 = state;
    var a: u64 = 0;
    var b: u64 = 0;
    if bytes.len() <= 16 {
        if bytes.len() >= 4 {
            const end = bytes.len() - 4;
            const quarter = (bytes.len() >> 3) << 2;
            a = (read(bytes, 0, 4) << 32) | read(bytes, quarter, 4);
            b = (read(bytes, end, 4) << 32) | read(bytes, end - quarter, 4);
        } else if bytes.len() > 0 {
            a = ((bytes[0] as u64) << 16) | ((bytes[bytes.len() >> 1] as u64) << 8) | (bytes[bytes.len() - 1] as u64);
        }
    } else {
        var i: usize = 0;
        if bytes.len() >= 48 {
            while i + 48 < bytes.len() {
                state = mix(read(bytes, i, 8) ^ s1, read(bytes, i + 8, 8) ^ state);
                state1 = mix(read(bytes, i + 16, 8) ^ s2, read(bytes, i + 24, 8) ^ state1);
                state2 = mix(read(bytes, i + 32, 8) ^ s3, read(bytes, i + 40, 8) ^ state2);
                i = i + 48;
            }
            state = state ^ state1 ^ state2;
        }
        while i + 16 < bytes.len() {
            state = mix(read(bytes, i, 8) ^ s1, read(bytes, i + 8, 8) ^ state);
            i = i + 16;
        }
        a = read(bytes, bytes.len() - 16, 8);
        b = read(bytes, bytes.len() - 8, 8);
    }
    const value = product(a ^ s1, b ^ state);
    return mix(value.low ^ s0 ^ (bytes.len() as u64), value.high ^ s1);
}
pub fn compute(source_path: string): string {
    const value = hash(source_path.bytes(), 0);
    const digits = "0123456789ABCDEF".bytes();
    var bytes = list<u8>();
    bytes.push(119);
    var i: usize = 0;
    while i < 16 {
        const shift = (15 - i) * 4;
        const digit = ((value >> shift) & 15) as usize;
        bytes.push(digits[digit]);
        i = i + 1;
    }
    return string.from(bytes.view());
}

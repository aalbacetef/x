const std = @import("std");
const C = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
});

const WindowErrors = error{
    CouldNotGetWindowListRef,
};

pub const WindowList = struct {
    ref: C.CFArrayRef,

    pub fn init() !WindowList {
        const arrayRef = C.CGWindowListCopyWindowInfo(
            C.kCGWindowListOptionAll,
            C.kCGNullWindowID,
        );

        if (arrayRef == null) {
            return WindowErrors.CouldNotGetWindowListRef;
        }

        return .{ .ref = arrayRef };
    }

    pub fn count(self: WindowList) usize {
        const index = C.CFArrayGetCount(self.ref);
        const n: usize = @intCast(index);

        return n;
    }

    pub fn makeWindows(self: WindowList, alloc: std.mem.Allocator, windows: []Window, n: usize) !void {
        for (0..n) |k| {
            const idx: c_long = @intCast(k);
            const v = C.CFArrayGetValueAtIndex(self.ref, idx);
            if (v) |dict_ref| {
                const val: C.CFDictionaryRef = @ptrCast(dict_ref);
                windows[k] = try Window.fromCFDictionary(alloc, val);
            }
        }
    }

    pub fn debug(self: WindowList) void {
        C.CFShow(self.ref);
    }

    pub fn deinit(self: WindowList) void {
        C.CFRelease(self.ref);
    }
};

pub const Window = struct {
    alpha: f64,
    id: u64,
    owner_name: ?[]u8 = null,
    name: ?[]u8 = null,
    owner_pid: u64,
    bounds: Rect,

    alloc: std.mem.Allocator,

    pub fn fromCFDictionary(alloc: std.mem.Allocator, dict: C.CFDictionaryRef) !Window {
        var alpha: f64 = 0;
        var id: u64 = 0;
        var owner_pid: u64 = 0;

        try numberFrom(f64, dict, C.kCGWindowAlpha, &alpha);
        try numberFrom(u64, dict, C.kCGWindowNumber, &id);
        try numberFrom(u64, dict, C.kCGWindowOwnerPID, &owner_pid);

        var rect: Rect = undefined;
        try rectFrom(dict, &rect);

        const owner_name = try strFrom(alloc, dict, C.kCGWindowOwnerName);
        const name = try strFrom(alloc, dict, C.kCGWindowName);

        return .{
            .alloc = alloc,
            .bounds = rect,
            .alpha = alpha,
            .id = id,
            .owner_pid = owner_pid,
            .owner_name = owner_name,
            .name = name,
        };
    }

    pub fn deinit(self: Window) !void {
        if (self.name) |name| {
            self.alloc.free(name);
        }

        if (self.owner_name) |owner_name| {
            self.alloc.free(owner_name);
        }
    }

    pub fn print(self: Window) void {
        std.debug.print("-----\n", .{});
        std.debug.print("  alpha: {d}\n", .{self.alpha});
        if (self.owner_name) |owner_name| {
            std.debug.print("  owner_name: {s}\n", .{owner_name});
        }
        if (self.name) |name| {
            std.debug.print("  name: {s}\n", .{name});
        }

        std.debug.print(
            "  bounds: (w={d}, h={d}) @ (x={d}, y={d})\n",
            .{ self.bounds.w, self.bounds.h, self.bounds.x, self.bounds.y },
        );
        std.debug.print("  owner pid: {d}\n", .{self.owner_pid});
        std.debug.print("  id: {d}\n", .{self.id});
    }
};

const ConvError = error{
    WrongDesiredType,
    NotSuccessful,
    DictReturnedNull,
    CouldNotDecodeRect,
    UTF8EncodingFailed,
};

const Rect = struct { w: f64, h: f64, x: f64, y: f64 };

fn rectFrom(dict: C.CFDictionaryRef, rect_ptr: *Rect) !void {
    const bounds_ref = C.CFDictionaryGetValue(dict, C.kCGWindowBounds);
    if (bounds_ref) |_ref| {
        const ref: C.CFDictionaryRef = @ptrCast(_ref);

        var raw_rect: C.CGRect = undefined;

        if (!C.CGRectMakeWithDictionaryRepresentation(ref, &raw_rect)) {
            return ConvError.CouldNotDecodeRect;
        }

        rect_ptr.* = .{
            .x = raw_rect.origin.x,
            .y = raw_rect.origin.y,
            .w = raw_rect.size.width,
            .h = raw_rect.size.height,
        };

        return;
    }

    return ConvError.CouldNotDecodeRect;
}

fn numberFrom(comptime T: type, dict: C.CFDictionaryRef, key: ?*const anyopaque, target: *T) !void {
    const convType = switch (T) {
        f64 => C.kCFNumberFloat64Type,
        u64 => C.kCFNumberLongLongType,
        else => return ConvError.WrongDesiredType,
    };

    const raw = C.CFDictionaryGetValue(dict, key);
    if (raw) |v| {
        const num_ref: C.CFNumberRef = @ptrCast(v);
        if (C.CFNumberGetValue(num_ref, convType, target) == 0) {
            return ConvError.NotSuccessful;
        }

        return;
    }

    return ConvError.DictReturnedNull;
}

fn strFrom(
    alloc: std.mem.Allocator,
    dict: C.CFDictionaryRef,
    key: ?*const anyopaque,
) !?[]u8 {
    const raw_val = C.CFDictionaryGetValue(dict, key);
    const encoding = C.kCFStringEncodingUTF8;

    if (raw_val) |v| {
        const raw: C.CFStringRef = @ptrCast(v);
        const chars = C.CFStringGetLength(raw);
        const len = C.CFStringGetMaximumSizeForEncoding(chars, encoding) + 1;
        const n: usize = @intCast(len);
        const s: []u8 = try alloc.alloc(u8, n);

        if (C.CFStringGetCString(raw, s.ptr, len, encoding) == 0) {
            return ConvError.UTF8EncodingFailed;
        }

        return s;
    }

    return null;
}

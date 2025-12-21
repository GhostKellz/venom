//! VENOM HUD Renderer
//!
//! Renders nvhud overlay content to the compositor output.
//! Supports both software rendering (for debug/testing) and
//! hardware-accelerated rendering via wlroots/EGL.

const std = @import("std");
const nvprime = @import("nvprime");
const hud = @import("hud.zig");

const RenderCommand = nvprime.nvhud.RenderCommand;
const Color = nvprime.nvhud.Color;

/// Render target type
pub const TargetType = enum {
    /// Software rendering to memory buffer
    software,
    /// Debug output (logs commands)
    debug,
    /// wlroots scene graph
    wlroots_scene,
    /// Direct EGL rendering
    egl,
};

/// RGBA pixel
pub const Pixel = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn fromColor(color: Color) Pixel {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
};

/// Software framebuffer for debug rendering
pub const Framebuffer = struct {
    width: u32,
    height: u32,
    pixels: []Pixel,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Framebuffer {
        const size = @as(usize, width) * @as(usize, height);
        const pixels = try allocator.alloc(Pixel, size);
        @memset(pixels, Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 });
        return .{
            .width = width,
            .height = height,
            .pixels = pixels,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Framebuffer) void {
        self.allocator.free(self.pixels);
    }

    pub fn clear(self: *Framebuffer) void {
        @memset(self.pixels, Pixel{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }

    pub fn setPixel(self: *Framebuffer, x: i32, y: i32, pixel: Pixel) void {
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;
        const idx = @as(usize, uy) * @as(usize, self.width) + @as(usize, ux);
        self.pixels[idx] = pixel;
    }

    pub fn fillRect(self: *Framebuffer, x: i32, y: i32, w: u32, h: u32, pixel: Pixel) void {
        var py: i32 = y;
        const end_y = y + @as(i32, @intCast(h));
        while (py < end_y) : (py += 1) {
            var px: i32 = x;
            const end_x = x + @as(i32, @intCast(w));
            while (px < end_x) : (px += 1) {
                self.setPixel(px, py, pixel);
            }
        }
    }
};

/// HUD Renderer
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    target_type: TargetType,
    framebuffer: ?Framebuffer = null,
    last_render_time_ns: u64 = 0,
    render_count: u64 = 0,

    // Render stats
    rects_rendered: u32 = 0,
    text_rendered: u32 = 0,
    bars_rendered: u32 = 0,
    graphs_rendered: u32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, target_type: TargetType) Self {
        return .{
            .allocator = allocator,
            .target_type = target_type,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.framebuffer) |*fb| {
            fb.deinit();
        }
    }

    /// Ensure framebuffer is allocated for software rendering
    pub fn ensureFramebuffer(self: *Self, width: u32, height: u32) !void {
        if (self.framebuffer) |*fb| {
            if (fb.width == width and fb.height == height) return;
            fb.deinit();
        }
        self.framebuffer = try Framebuffer.init(self.allocator, width, height);
    }

    /// Render HUD commands
    pub fn render(self: *Self, hud_ctx: *hud.Hud, width: u32, height: u32) !void {
        const start_time = std.time.nanoTimestamp();

        // Reset stats
        self.rects_rendered = 0;
        self.text_rendered = 0;
        self.bars_rendered = 0;
        self.graphs_rendered = 0;

        // Get render commands from nvhud
        const commands = hud_ctx.getRenderCommands();

        switch (self.target_type) {
            .debug => self.renderDebug(commands),
            .software => {
                try self.ensureFramebuffer(width, height);
                self.renderSoftware(commands);
            },
            .wlroots_scene => self.renderWlroots(commands),
            .egl => self.renderEgl(commands),
        }

        // Render venom-specific extra lines
        self.renderExtraLines(hud_ctx);

        const end_time = std.time.nanoTimestamp();
        self.last_render_time_ns = @intCast(end_time - start_time);
        self.render_count += 1;
    }

    /// Debug renderer - logs commands to stderr
    fn renderDebug(self: *Self, commands: []const RenderCommand) void {
        if (commands.len == 0) return;

        for (commands) |cmd| {
            switch (cmd) {
                .rect => |r| {
                    std.log.debug("[HUD] Rect: {}x{} at ({},{})", .{ r.width, r.height, r.x, r.y });
                    self.rects_rendered += 1;
                },
                .text => |t| {
                    std.log.debug("[HUD] Text: \"{s}\" at ({},{})", .{ t.text, t.x, t.y });
                    self.text_rendered += 1;
                },
                .bar => |b| {
                    std.log.debug("[HUD] Bar: {d:.0}% at ({},{})", .{ b.value * 100, b.x, b.y });
                    self.bars_rendered += 1;
                },
                .graph => |g| {
                    std.log.debug("[HUD] Graph: {} values at ({},{})", .{ g.values.len, g.x, g.y });
                    self.graphs_rendered += 1;
                },
            }
        }
    }

    /// Software renderer - renders to framebuffer
    fn renderSoftware(self: *Self, commands: []const RenderCommand) void {
        const fb = &(self.framebuffer orelse return);
        fb.clear();

        for (commands) |cmd| {
            switch (cmd) {
                .rect => |r| {
                    fb.fillRect(r.x, r.y, r.width, r.height, Pixel.fromColor(r.color));
                    self.rects_rendered += 1;
                },
                .text => |t| {
                    // Simple text rendering - draw character boxes
                    const char_w: u32 = 8;
                    const char_h: u32 = 16;
                    var cx: i32 = t.x;
                    for (t.text) |_| {
                        fb.fillRect(cx, t.y, char_w, char_h, Pixel.fromColor(t.color));
                        cx += @intCast(char_w);
                    }
                    self.text_rendered += 1;
                },
                .bar => |b| {
                    // Background
                    fb.fillRect(b.x, b.y, b.width, b.height, Pixel.fromColor(b.bg_color));
                    // Foreground
                    const fill_w: u32 = @intFromFloat(@as(f32, @floatFromInt(b.width)) * b.value);
                    fb.fillRect(b.x, b.y, fill_w, b.height, Pixel.fromColor(b.color));
                    self.bars_rendered += 1;
                },
                .graph => |g| {
                    // Simple graph - draw vertical bars
                    const max_val = blk: {
                        var m: f32 = 0;
                        for (g.values) |v| m = @max(m, v);
                        break :blk if (m > 0) m else 1;
                    };
                    const bar_w: u32 = if (g.values.len > 0) g.width / @as(u32, @intCast(g.values.len)) else 1;
                    var gx: i32 = g.x;
                    for (g.values) |v| {
                        const bar_h: u32 = @intFromFloat((v / max_val) * @as(f32, @floatFromInt(g.height)));
                        const bar_y = g.y + @as(i32, @intCast(g.height - bar_h));
                        fb.fillRect(gx, bar_y, bar_w, bar_h, Pixel.fromColor(g.color));
                        gx += @intCast(bar_w);
                    }
                    self.graphs_rendered += 1;
                },
            }
        }
    }

    /// wlroots scene graph renderer (stub - needs wlroots integration)
    fn renderWlroots(self: *Self, commands: []const RenderCommand) void {
        // When wlroots is integrated, this will create scene nodes
        // for each command and attach them to the scene graph
        _ = self;
        _ = commands;
    }

    /// EGL renderer (stub - needs EGL integration)
    fn renderEgl(self: *Self, commands: []const RenderCommand) void {
        // When EGL is integrated, this will use OpenGL ES to render
        _ = self;
        _ = commands;
    }

    /// Render venom-specific extra HUD lines
    fn renderExtraLines(self: *Self, hud_ctx: *hud.Hud) void {
        const extra_count = hud_ctx.getExtraLinesCount();
        if (extra_count == 0) return;

        for (0..extra_count) |i| {
            if (hud_ctx.getExtraLine(i)) |line| {
                switch (self.target_type) {
                    .debug => std.log.debug("[HUD] Extra: \"{s}\"", .{line}),
                    else => {},
                }
            }
        }
    }

    /// Get render time in microseconds
    pub fn getRenderTimeUs(self: *const Self) u64 {
        return self.last_render_time_ns / 1000;
    }

    /// Get render stats summary
    pub fn getStats(self: *const Self) struct {
        render_count: u64,
        render_time_us: u64,
        rects: u32,
        text: u32,
        bars: u32,
        graphs: u32,
    } {
        return .{
            .render_count = self.render_count,
            .render_time_us = self.getRenderTimeUs(),
            .rects = self.rects_rendered,
            .text = self.text_rendered,
            .bars = self.bars_rendered,
            .graphs = self.graphs_rendered,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "framebuffer init" {
    const fb = try Framebuffer.init(std.testing.allocator, 100, 100);
    defer @constCast(&fb).deinit();

    try std.testing.expectEqual(@as(u32, 100), fb.width);
    try std.testing.expectEqual(@as(usize, 10000), fb.pixels.len);
}

test "renderer debug mode" {
    var renderer = Renderer.init(std.testing.allocator, .debug);
    defer renderer.deinit();

    try std.testing.expectEqual(TargetType.debug, renderer.target_type);
}

const std = @import("std");
const glfw = @import("glfw");

const ps = std.process;
const log = std.log;

const WIDTH = 800;
const HEIGHT = 640;
const TITLE = "wgpu shader toy";

pub fn main() !void {
    // Initialize GLFW

    glfw.setErrorCallback(errorCallback);

    const init_successfully = glfw.init(.{});
    defer glfw.terminate();

    if (!init_successfully) {
        log.err("Failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        ps.exit(1);
    }

    // Create window

    const win = glfw.Window.create(WIDTH, HEIGHT, TITLE, null, null, .{}) orelse {
        log.err("Failed to create Window: {?s}", .{glfw.getErrorString()});
        ps.exit(1);
    };

    defer win.destroy();

    while (!win.shouldClose()) {
        glfw.pollEvents();
    }
}

fn errorCallback(code: glfw.ErrorCode, desc: [:0]const u8) void {
    log.err("GLFW Error [{}] : {s}", .{ code, desc });
}

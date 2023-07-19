const std = @import("std");
const gpu = @import("gpu");
const glfw = @import("glfw");
const ps = std.process;
const log = std.log;

const Config = struct {
    window_title: [*:0]const u8 = "Hello WGPU",
    window_width: u32 = 800,
    window_height: u32 = 600,
    key_callback: ?KeyCallback = null,
};

pub const Context = struct {
    device: *gpu.Device,
    queue: *gpu.Queue,
    swap_chain: *gpu.SwapChain,
    width: f32,
    height: f32,
};

pub const Setup = struct {
    const Self = @This();

    window: glfw.Window,
    instance: *gpu.Instance,
    surface: *gpu.Surface,
    adapter: *gpu.Adapter,
    device: *gpu.Device,
    queue: *gpu.Queue,
    swap_chain: *gpu.SwapChain,

    pub fn nextFrame(self: *Self) ?Context {
        glfw.pollEvents();

        if (self.window.shouldClose()) return null;

        const size = self.window.getFramebufferSize();

        const swap_desc: gpu.SwapChain.Descriptor = .{
            .label = "basic swap chain",
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .width = size.width,
            .height = size.height,
            .present_mode = .fifo,
        };

        self.swap_chain = self.device.createSwapChain(self.surface, &swap_desc);

        return .{
            .device = self.device,
            .queue = self.queue,
            .swap_chain = self.swap_chain,
            .width = @intToFloat(f32, size.width),
            .height = @intToFloat(f32, size.height),
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.destroy();
        glfw.terminate();
    }
};

pub fn setup(comptime cfg: Config) Setup {
    // Initialize GPU
    gpu.Impl.init();

    // Initialize GLFW
    glfw.setErrorCallback(errorCallback);

    const success = glfw.init(.{ .platform = .wayland });

    if (!success) {
        log.err("Failed to initialize GLFW: {?s}\n", .{glfw.getErrorString()});
        ps.exit(1);
    }

    // Initialize Window
    const win = glfw.Window.create(
        cfg.window_width,
        cfg.window_height,
        cfg.window_title,
        null,
        null,
        .{},
    ) orelse {
        log.err("Failed to create Window: {?s}\n", .{glfw.getErrorString()});
        ps.exit(1);
    };

    win.setKeyCallback(cfg.key_callback);

    // Get Instance
    const instance = gpu.createInstance(null) orelse {
        log.err("Failed to create GPU instance \n", .{});
        ps.exit(1);
    };

    // Get Surface
    const glfw_native = glfw.Native(.{ .wayland = true });

    const surface_desc: gpu.Surface.Descriptor = .{
        .next_in_chain = .{ .from_wayland_surface = &.{
            .display = glfw_native.getWaylandDisplay(),
            .surface = glfw_native.getWaylandWindow(win),
        } },
    };

    const surface = instance.createSurface(&surface_desc);

    // Get Adapter

    const adapter_opts: gpu.RequestAdapterOptions = .{
        .compatible_surface = surface,
        .power_preference = .undefined,
        .force_fallback_adapter = false,
    };

    var response: ?RequestAdapterResponse = null;
    instance.requestAdapter(&adapter_opts, &response, requestAdapterCallback);

    if (response.?.status != .success) {
        std.log.err("Could not get Adapter: {s}\n", .{response.?.message.?});
        ps.exit(1);
    }

    const adapter = response.?.adapter;

    var props = std.mem.zeroes(gpu.Adapter.Properties);
    adapter.getProperties(&props);

    std.log.info("\nfound {s} backend on {s}\n\tadapter = {s}, {s}\n", .{
        props.backend_type.name(),
        props.adapter_type.name(),
        props.name,
        props.driver_description,
    });

    // Create Device

    const device = adapter.createDevice(null) orelse {
        std.log.err("Failed to create GPU device.\n", .{});
        ps.exit(1);
    };

    device.setUncapturedErrorCallback({}, printUnhandledErrorCallback);

    // Get Queue
    const queue = device.getQueue();

    // Get SwapChain
    const size = win.getFramebufferSize();

    const swap_desc: gpu.SwapChain.Descriptor = .{
        .label = "basic swap chain",
        .usage = .{ .render_attachment = true },
        .format = .bgra8_unorm,
        .width = size.width,
        .height = size.height,
        .present_mode = .fifo,
    };

    const swap_chain = device.createSwapChain(surface, &swap_desc);

    // Return Context
    return .{
        .window = win,
        .instance = instance,
        .surface = surface,
        .adapter = adapter,
        .device = device,
        .queue = queue,
        .swap_chain = swap_chain,
    };
}

// Custom Types

const RequestAdapterResponse = struct {
    status: gpu.RequestAdapterStatus,
    adapter: *gpu.Adapter,
    message: ?[*:0]const u8,
};

const KeyCallback = fn (
    window: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) void;

// Error Callbacks

fn errorCallback(code: glfw.ErrorCode, desc: [:0]const u8) void {
    log.err("GLFW Error [{}] : {s}\n", .{ code, desc });
}

inline fn requestAdapterCallback(
    context: *?RequestAdapterResponse,
    status: gpu.RequestAdapterStatus,
    adapter: *gpu.Adapter,
    message: ?[*:0]const u8,
) void {
    context.* = RequestAdapterResponse{
        .adapter = adapter,
        .status = status,
        .message = message,
    };
}

inline fn printUnhandledErrorCallback(
    _: void,
    typ: gpu.ErrorType,
    message: [*:0]const u8,
) void {
    switch (typ) {
        .validation => log.err("gpu: validation error: {s}\n", .{message}),
        .out_of_memory => log.err("gpu: out_of_memory error: {s}\n", .{message}),
        .device_lost => log.err("gpu: device_lost error: {s}\n", .{message}),
        .unknown => log.err("gpu: unknown error: {s}\n", .{message}),
        else => unreachable,
    }
    ps.exit(1);
}

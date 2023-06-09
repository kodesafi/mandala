const std = @import("std");
const gpu = @import("gpu");
const glfw = @import("glfw");

const ps = std.process;
const log = std.log;

const WIDTH = 800;
const HEIGHT = 640;
const TITLE = "wgpu shader toy";

pub const GPUInterface = gpu.dawn.Interface;

pub fn main() !void {
    gpu.Impl.init();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    // Initialize GLFW

    glfw.setErrorCallback(errorCallback);

    const init_successfully = glfw.init(.{ .platform = .wayland });
    defer glfw.terminate();

    if (!init_successfully) {
        log.err("Failed to initialize GLFW: {?s}\n", .{glfw.getErrorString()});
        ps.exit(1);
    }

    // Create window

    const win = glfw.Window.create(WIDTH, HEIGHT, TITLE, null, null, .{}) orelse {
        log.err("Failed to create Window: {?s}\n", .{glfw.getErrorString()});
        ps.exit(1);
    };

    defer win.destroy();

    win.setFramebufferSizeCallback(handleResize);
    win.setKeyCallback(handleKeyPress);

    // Get instance

    const instance = gpu.createInstance(null) orelse {
        log.err("Failed to create GPU instance \n", .{});
        ps.exit(1);
    };

    // Get surface

    const glfw_native = glfw.Native(.{ .wayland = true });

    const surface_desc: gpu.Surface.Descriptor = .{
        .next_in_chain = .{ .from_wayland_surface = &.{
            .display = glfw_native.getWaylandDisplay(),
            .surface = glfw_native.getWaylandWindow(win),
        } },
    };

    const surface = instance.createSurface(&surface_desc);

    // Create Surface Data

    const fb_size = win.getFramebufferSize();

    const data = try ally.create(SurfaceData);

    const swap_desc: gpu.SwapChain.Descriptor = .{
        .label = "basic swap chain",
        .usage = .{ .render_attachment = true },
        .format = .bgra8_unorm,
        .width = fb_size.width,
        .height = fb_size.height,
        .present_mode = .fifo,
    };

    data.* = .{
        .surface = surface,
        .swap_chain = null,
        .current_desc = swap_desc,
        .target_desc = swap_desc,
    };

    win.setUserPointer(data);

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

    std.log.info("\nfound {s} backend on {s}\n\tadaper = {s}, {s}\n", .{
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

    // Configure Shaders
    const vs =
        \\ @vertex fn main( 
        \\     @builtin(vertex_index) VertexIndex: u32 
        \\ ) -> @builtin(position) vec4<f32> {
        \\     var pos = array<vec2<f32>, 3>(
        \\         vec2<f32>(0.0, 0.5),
        \\         vec2<f32>(-0.5, -0.5),
        \\         vec2<f32>(0.5, -0.5),
        \\     );
        \\     return vec4<f32>(pos[VertexIndex], 0.0,1.0);
        \\ }
    ;

    const vs_module = device.createShaderModuleWGSL("vertex shader", vs);

    const fs =
        \\ @fragment fn main() -> @location(0) vec4<f32> {
        \\     return vec4<f32>(1.0, 0.0, 0.0, 1.0);
        \\ }
    ;

    const fs_module = device.createShaderModuleWGSL("fragment shader", fs);

    const color_target = gpu.ColorTargetState{
        .format = .bgra8_unorm,
        .blend = &gpu.BlendState{
            .color = .{ .dst_factor = .one },
            .alpha = .{ .dst_factor = .one },
        },
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };

    const fragment = gpu.FragmentState.init(.{
        .module = fs_module,
        .entry_point = "main",
        .targets = &.{color_target},
    });

    const pipeline_desc = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = null,
        .depth_stencil = null,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
        },
        .multisample = .{},
        .primitive = .{},
    };

    const pipeline = device.createRenderPipeline(&pipeline_desc);

    vs_module.release();
    fs_module.release();

    // Get Queue

    const queue = device.getQueue();

    // Event loop;

    while (!win.shouldClose()) {
        glfw.pollEvents();

        const pl = win.getUserPointer(SurfaceData).?;
        const has_resized = !std.meta.eql(pl.current_desc, pl.target_desc);

        if (pl.swap_chain == null or has_resized) {
            pl.swap_chain = device.createSwapChain(pl.surface, &pl.target_desc);
            pl.current_desc = pl.target_desc;
        }

        const back_buffer_view = pl.swap_chain.?.getCurrentTextureView();

        const color_attachment = gpu.RenderPassColorAttachment{
            .view = back_buffer_view,
            .resolve_target = null,
            .clear_value = std.mem.zeroes(gpu.Color),
            .load_op = .clear,
            .store_op = .store,
        };

        const encoder = device.createCommandEncoder(null);

        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });

        const pass = encoder.beginRenderPass(&render_pass_info);
        pass.setPipeline(pipeline);
        pass.draw(3, 1, 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        encoder.release();

        queue.submit(&[_]*gpu.CommandBuffer{command});
        command.release();
        pl.swap_chain.?.present();
        back_buffer_view.release();

        std.time.sleep(16 * std.time.ns_per_ms);
    }
}

fn handleResize(win: glfw.Window, width: u32, height: u32) void {
    const pl = win.getUserPointer(SurfaceData);
    pl.?.target_desc.width = width;
    pl.?.target_desc.height = height;
}

fn handleKeyPress(
    win: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods,
) void {
    if (key == .q) win.setShouldClose(true);
    _ = mods;
    _ = action;
    _ = scancode;
}

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

const SurfaceData = struct {
    const Self = @This();

    surface: ?*gpu.Surface,
    swap_chain: ?*gpu.SwapChain,
    current_desc: gpu.SwapChain.Descriptor,
    target_desc: gpu.SwapChain.Descriptor,
};

const RequestAdapterResponse = struct {
    status: gpu.RequestAdapterStatus,
    adapter: *gpu.Adapter,
    message: ?[*:0]const u8,
};

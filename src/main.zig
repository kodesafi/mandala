const std = @import("std");
const gpu = @import("gpu");
const glfw = @import("glfw");
const util = @import("utils.zig");

const ps = std.process;
const log = std.log;

const Vertex = struct {
    position: [2]f32,
    color: [3]f32,
};

const Uniforms = packed struct {
    time: f32,
    width: f32,
    height: f32,

    fn flatten(self: *Uniforms) [3]f32 {
        return [_]f32{ self.time, self.width, self.height };
    }
};

const VERTICES = [_]Vertex{
    .{ .position = .{ -1.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0 } },
    .{ .position = .{ 1.0, 1.0 }, .color = .{ 0.0, 1.0, 0.0 } },
    .{ .position = .{ 1.0, -1.0 }, .color = .{ 0.0, 0.0, 1.0 } },
    .{ .position = .{ -1.0, -1.0 }, .color = .{ 1.0, 1.0, 1.0 } },
};

const INDICES = [_]u16{ 0, 2, 1, 0, 3, 2 };

pub const GPUInterface = gpu.dawn.Interface;

pub fn main() !void {
    defer log.info("Closing norminally =)", .{});

    var cx = util.setup(.{ .key_callback = handleKeyPress });
    defer cx.deinit();

    // Configure Shaders
    const shader = @embedFile("shader.wgsl");

    const shader_module = cx.device.createShaderModuleWGSL("default shader", shader);

    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "fs_main",
        .targets = &.{.{
            .format = .bgra8_unorm,
            .blend = &gpu.BlendState{
                .color = .{ .dst_factor = .one },
                .alpha = .{ .dst_factor = .one },
            },
            .write_mask = gpu.ColorWriteMaskFlags.all,
        }},
    });

    const vb_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .attributes = &[_]gpu.VertexAttribute{
            .{
                .format = .float32x2,
                .offset = 0,
                .shader_location = 0,
            },
            .{
                .format = .float32x3,
                .offset = @sizeOf([2]f32),
                .shader_location = 1,
            },
        },
    });

    const vertex = gpu.VertexState.init(.{
        .module = shader_module,
        .entry_point = "vs_main",
        .buffers = &[_]gpu.VertexBufferLayout{vb_layout},
    });

    // Create Buffers
    const vertex_buffer = cx.device.createBuffer(&.{
        .label = "Vertex Buffer",
        .usage = .{
            .vertex = true,
            .copy_dst = true,
        },
        .size = @sizeOf(Vertex) * VERTICES.len,
    });

    cx.queue.writeBuffer(vertex_buffer, 0, &VERTICES);

    const index_buffer = cx.device.createBuffer(&.{
        .label = "Index Buffer",
        .usage = .{
            .index = true,
            .copy_dst = true,
        },
        .size = @sizeOf(u16) * INDICES.len,
    });

    cx.queue.writeBuffer(index_buffer, 0, &INDICES);

    const uniform_buffer = cx.device.createBuffer(&.{
        .label = "Uniform Buffer",
        .usage = .{
            .uniform = true,
            .copy_dst = true,
        },
        .size = @sizeOf(Uniforms),
    });

    // Set up Bind groups
    const uniform_layout_desc = gpu.BindGroupLayout.Descriptor.init(.{
        .label = "Uniform bind group layout",
        .entries = &[_]gpu.BindGroupLayout.Entry{.{
            .binding = 0,
            .visibility = .{
                .vertex = true,
                .fragment = true,
            },
            .buffer = .{
                .type = .uniform,
                .has_dynamic_offset = false,
                .min_binding_size = 0,
            },
        }},
    });

    const uniform_bind_layout = cx.device.createBindGroupLayout(&uniform_layout_desc);

    const uniform_bind_desc = gpu.BindGroup.Descriptor.init(.{
        .label = "uniform bind group",
        .layout = uniform_bind_layout,
        .entries = &[_]gpu.BindGroup.Entry{.{
            .binding = 0,
            .buffer = uniform_buffer,
            .size = @sizeOf(Uniforms),
        }},
    });

    const uniform_bind_group = cx.device.createBindGroup(&uniform_bind_desc);

    // Configure Render Pipeline
    const layout_desc = gpu.PipelineLayout.Descriptor.init(.{
        .label = "Render Pipeline Layout",
        .bind_group_layouts = &[_]*gpu.BindGroupLayout{uniform_bind_layout},
    });

    const layout = cx.device.createPipelineLayout(&layout_desc);

    const pipeline_desc = gpu.RenderPipeline.Descriptor{
        .label = "render pipeline",
        .layout = layout,
        .fragment = &fragment,
        .depth_stencil = null,
        .vertex = vertex,
        .multisample = .{},
        .primitive = .{ .cull_mode = .back },
    };

    const pipeline = cx.device.createRenderPipeline(&pipeline_desc);
    shader_module.release();

    // Event loop;
    const size = cx.window.getFramebufferSize();

    var uniforms: Uniforms = .{
        .time = 0.0,
        .width = @intToFloat(f32, size.width),
        .height = @intToFloat(f32, size.height),
    };

    cx.queue.writeBuffer(uniform_buffer, 0, &uniforms.flatten());

    while (cx.nextFrame()) |ctx| {
        const buffer_view = ctx.swap_chain.getCurrentTextureView();

        const color_attachment = gpu.RenderPassColorAttachment{
            .view = buffer_view,
            .clear_value = gpu.Color{
                .r = 0.0,
                .g = 0.0,
                .b = 0.0,
                .a = 1.0,
            },
            .load_op = .clear,
            .store_op = .store,
        };

        const render_pass_info = gpu.RenderPassDescriptor.init(.{
            .color_attachments = &.{color_attachment},
        });

        const encoder = ctx.device.createCommandEncoder(null);
        defer encoder.release();

        const pass = encoder.beginRenderPass(&render_pass_info);

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, uniform_bind_group, null);
        pass.setVertexBuffer(0, vertex_buffer, 0, gpu.whole_size);
        pass.setIndexBuffer(index_buffer, .uint16, 0, gpu.whole_size);
        pass.drawIndexed(INDICES.len, 1, 0, 0, 0);
        pass.end();
        pass.release();

        var command = encoder.finish(null);
        defer command.release();

        cx.queue.submit(&[_]*gpu.CommandBuffer{command});
        ctx.swap_chain.present();

        std.time.sleep(16 * std.time.ns_per_ms);
        uniforms.time += 16.0;
        uniforms.width = ctx.width;
        uniforms.height = ctx.height;
        cx.queue.writeBuffer(uniform_buffer, 0, &uniforms.flatten());
    }
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

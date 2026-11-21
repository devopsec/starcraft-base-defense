//! wgpu-native renderer: one instanced-cube pipeline draws the arena, enemies, effects and crosshair.
//! The surface comes from the SDL3 window (Wayland, X11 or Win32). All GPU buffers are created up front.
const std = @import("std");
const c = @import("c");
const game_mod = @import("game.zig");
const core = @import("sbd_core");

const V3 = game_mod.V3;
const T = core.types;

const shader_src =
    \\struct Globals { view_proj: mat4x4<f32>, light: vec4<f32>, tint: vec4<f32> };
    \\@group(0) @binding(0) var<uniform> g: Globals;
    \\struct VsIn {
    \\  @location(0) pos: vec3<f32>, @location(1) normal: vec3<f32>,
    \\  @location(2) center: vec4<f32>, @location(3) scale: vec4<f32>, @location(4) color: vec4<f32>,
    \\};
    \\struct VsOut { @builtin(position) clip: vec4<f32>, @location(0) normal: vec3<f32>, @location(1) color: vec4<f32> };
    \\@vertex fn vs(i: VsIn) -> VsOut {
    \\  var o: VsOut;
    \\  let world = i.center.xyz + i.pos * i.scale.xyz;
    \\  o.clip = g.view_proj * vec4<f32>(world, 1.0);
    \\  o.normal = i.normal;
    \\  o.color = i.color;
    \\  return o;
    \\}
    \\@fragment fn fs(i: VsOut) -> @location(0) vec4<f32> {
    \\  let l = max(dot(normalize(i.normal), normalize(g.light.xyz)), 0.0);
    \\  let lit = i.color.rgb * (0.3 + 0.7 * l) + i.color.rgb * i.color.a;
    \\  return vec4<f32>(mix(lit, g.tint.rgb, g.tint.a), 1.0);
    \\}
;

const Vertex = extern struct { pos: [3]f32, normal: [3]f32 };
/// color.a is emissive strength (effects glow regardless of lighting).
pub const Instance = extern struct { center: [4]f32, scale: [4]f32, color: [4]f32 };
const Globals = extern struct { view_proj: [16]f32, light: [4]f32, tint: [4]f32 };

pub const max_instances = 1024;
const depth_format = c.WGPUTextureFormat_Depth24Plus;

pub const Gfx = struct {
    instance: c.WGPUInstance,
    surface: c.WGPUSurface,
    adapter: c.WGPUAdapter,
    device: c.WGPUDevice,
    queue: c.WGPUQueue,
    format: c.WGPUTextureFormat,
    pipeline: c.WGPURenderPipeline,
    bind_group: c.WGPUBindGroup,
    globals_buf: c.WGPUBuffer,
    vertex_buf: c.WGPUBuffer,
    instance_buf: c.WGPUBuffer,
    depth_tex: c.WGPUTexture = null,
    depth_view: c.WGPUTextureView = null,
    width: u32 = 0,
    height: u32 = 0,
    instances: [max_instances]Instance = undefined,
    count: u32 = 0,
    adapter_name: [128]u8 = undefined,
    adapter_name_len: usize = 0,

    pub fn init(self: *Gfx, window: *c.SDL_Window, width: u32, height: u32) !void {
        self.* = undefined;
        self.depth_tex = null;
        self.depth_view = null;
        self.count = 0;
        self.adapter_name_len = 0;

        self.instance = c.wgpuCreateInstance(null) orelse return error.WgpuInstance;
        self.surface = try createSurface(self.instance, window);

        var opts = std.mem.zeroes(c.WGPURequestAdapterOptions);
        opts.powerPreference = c.WGPUPowerPreference_HighPerformance;
        opts.compatibleSurface = self.surface;
        var adapter_req: Request(c.WGPUAdapter) = .{};
        var acb = std.mem.zeroes(c.WGPURequestAdapterCallbackInfo);
        acb.mode = c.WGPUCallbackMode_AllowProcessEvents;
        acb.callback = onAdapter;
        acb.userdata1 = &adapter_req;
        _ = c.wgpuInstanceRequestAdapter(self.instance, &opts, acb);
        while (!adapter_req.done) c.wgpuInstanceProcessEvents(self.instance);
        self.adapter = adapter_req.value orelse return error.WgpuNoAdapter;

        var info = std.mem.zeroes(c.WGPUAdapterInfo);
        if (c.wgpuAdapterGetInfo(self.adapter, &info) == c.WGPUStatus_Success) {
            const name = viewSlice(info.device);
            self.adapter_name_len = @min(name.len, self.adapter_name.len);
            @memcpy(self.adapter_name[0..self.adapter_name_len], name[0..self.adapter_name_len]);
            c.wgpuAdapterInfoFreeMembers(info);
        }

        var dd = std.mem.zeroes(c.WGPUDeviceDescriptor);
        dd.label = sv("sbd device");
        dd.uncapturedErrorCallbackInfo.callback = onDeviceError;
        var device_req: Request(c.WGPUDevice) = .{};
        var dcb = std.mem.zeroes(c.WGPURequestDeviceCallbackInfo);
        dcb.mode = c.WGPUCallbackMode_AllowProcessEvents;
        dcb.callback = onDevice;
        dcb.userdata1 = &device_req;
        _ = c.wgpuAdapterRequestDevice(self.adapter, &dd, dcb);
        while (!device_req.done) c.wgpuInstanceProcessEvents(self.instance);
        self.device = device_req.value orelse return error.WgpuNoDevice;
        self.queue = c.wgpuDeviceGetQueue(self.device);

        var caps = std.mem.zeroes(c.WGPUSurfaceCapabilities);
        if (c.wgpuSurfaceGetCapabilities(self.surface, self.adapter, &caps) != c.WGPUStatus_Success or caps.formatCount == 0)
            return error.WgpuSurfaceCaps;
        self.format = caps.formats[0];
        for (caps.formats[0..caps.formatCount]) |f| {
            if (f == c.WGPUTextureFormat_BGRA8UnormSrgb or f == c.WGPUTextureFormat_RGBA8UnormSrgb) {
                self.format = f;
                break;
            }
        }
        c.wgpuSurfaceCapabilitiesFreeMembers(caps);

        self.globals_buf = self.buffer("globals", @sizeOf(Globals), c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst);
        self.vertex_buf = self.buffer("cube", @sizeOf(@TypeOf(cube_vertices)), c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst);
        self.instance_buf = self.buffer("instances", @sizeOf(Instance) * max_instances, c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst);
        c.wgpuQueueWriteBuffer(self.queue, self.vertex_buf, 0, &cube_vertices, @sizeOf(@TypeOf(cube_vertices)));

        try self.createPipeline();
        self.resize(width, height);
    }

    pub fn deinit(self: *Gfx) void {
        if (self.depth_view) |v| c.wgpuTextureViewRelease(v);
        if (self.depth_tex) |t| c.wgpuTextureRelease(t);
        c.wgpuBindGroupRelease(self.bind_group);
        c.wgpuRenderPipelineRelease(self.pipeline);
        c.wgpuBufferRelease(self.instance_buf);
        c.wgpuBufferRelease(self.vertex_buf);
        c.wgpuBufferRelease(self.globals_buf);
        c.wgpuQueueRelease(self.queue);
        c.wgpuDeviceRelease(self.device);
        c.wgpuAdapterRelease(self.adapter);
        c.wgpuSurfaceRelease(self.surface);
        c.wgpuInstanceRelease(self.instance);
    }

    pub fn adapterName(self: *const Gfx) []const u8 {
        return self.adapter_name[0..self.adapter_name_len];
    }

    pub fn resize(self: *Gfx, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.width = width;
        self.height = height;
        var cfg = std.mem.zeroes(c.WGPUSurfaceConfiguration);
        cfg.device = self.device;
        cfg.format = self.format;
        cfg.usage = c.WGPUTextureUsage_RenderAttachment;
        cfg.width = width;
        cfg.height = height;
        cfg.alphaMode = c.WGPUCompositeAlphaMode_Auto;
        cfg.presentMode = c.WGPUPresentMode_Fifo;
        c.wgpuSurfaceConfigure(self.surface, &cfg);

        if (self.depth_view) |v| c.wgpuTextureViewRelease(v);
        if (self.depth_tex) |t| c.wgpuTextureRelease(t);
        var td = std.mem.zeroes(c.WGPUTextureDescriptor);
        td.label = sv("depth");
        td.usage = c.WGPUTextureUsage_RenderAttachment;
        td.dimension = c.WGPUTextureDimension_2D;
        td.size = .{ .width = width, .height = height, .depthOrArrayLayers = 1 };
        td.format = depth_format;
        td.mipLevelCount = 1;
        td.sampleCount = 1;
        self.depth_tex = c.wgpuDeviceCreateTexture(self.device, &td);
        self.depth_view = c.wgpuTextureCreateView(self.depth_tex, null);
    }

    /// Builds the instance list from game state and draws one frame. Returns false if the frame was skipped.
    pub fn render(self: *Gfx, g: *const game_mod.Game) bool {
        self.buildScene(g);

        var st = std.mem.zeroes(c.WGPUSurfaceTexture);
        c.wgpuSurfaceGetCurrentTexture(self.surface, &st);
        switch (st.status) {
            c.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal, c.WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal => {},
            c.WGPUSurfaceGetCurrentTextureStatus_Outdated, c.WGPUSurfaceGetCurrentTextureStatus_Lost => {
                if (st.texture) |t| c.wgpuTextureRelease(t);
                self.resize(self.width, self.height);
                return false;
            },
            else => {
                if (st.texture) |t| c.wgpuTextureRelease(t);
                return false;
            },
        }
        defer c.wgpuTextureRelease(st.texture);
        const view = c.wgpuTextureCreateView(st.texture, null);
        defer c.wgpuTextureViewRelease(view);

        const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(@max(self.height, 1)));
        const eye = g.player.eye();
        const proj = perspective(std.math.degreesToRadians(70.0), aspect, 0.05, 200);
        const viewm = lookAt(eye, eye + g.player.forward(), .{ 0, 1, 0 });
        var globals: Globals = .{ .view_proj = mul(proj, viewm), .light = .{ 0.4, 1.0, 0.3, 0 }, .tint = .{ 0, 0, 0, 0 } };
        if (g.player_flash > 0) globals.tint = .{ 0.8, 0.05, 0.05, g.player_flash * 1.6 };
        switch (g.state()) {
            T.State.paused => globals.tint = .{ 0.05, 0.05, 0.1, 0.55 },
            T.State.game_over => globals.tint = .{ 0.25, 0.0, 0.0, 0.5 },
            else => {},
        }
        c.wgpuQueueWriteBuffer(self.queue, self.globals_buf, 0, &globals, @sizeOf(Globals));
        c.wgpuQueueWriteBuffer(self.queue, self.instance_buf, 0, &self.instances, @sizeOf(Instance) * self.count);

        const enc = c.wgpuDeviceCreateCommandEncoder(self.device, null);
        defer c.wgpuCommandEncoderRelease(enc);
        var color = std.mem.zeroes(c.WGPURenderPassColorAttachment);
        color.view = view;
        color.depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED;
        color.loadOp = c.WGPULoadOp_Clear;
        color.storeOp = c.WGPUStoreOp_Store;
        color.clearValue = .{ .r = 0.02, .g = 0.03, .b = 0.06, .a = 1 };
        var depth = std.mem.zeroes(c.WGPURenderPassDepthStencilAttachment);
        depth.view = self.depth_view;
        depth.depthLoadOp = c.WGPULoadOp_Clear;
        depth.depthStoreOp = c.WGPUStoreOp_Discard;
        depth.depthClearValue = 1.0;
        var rp = std.mem.zeroes(c.WGPURenderPassDescriptor);
        rp.colorAttachmentCount = 1;
        rp.colorAttachments = &color;
        rp.depthStencilAttachment = &depth;
        const pass = c.wgpuCommandEncoderBeginRenderPass(enc, &rp);
        c.wgpuRenderPassEncoderSetPipeline(pass, self.pipeline);
        c.wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, null);
        c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, self.vertex_buf, 0, c.WGPU_WHOLE_SIZE);
        c.wgpuRenderPassEncoderSetVertexBuffer(pass, 1, self.instance_buf, 0, c.WGPU_WHOLE_SIZE);
        c.wgpuRenderPassEncoderDraw(pass, cube_vertices.len, self.count, 0, 0);
        c.wgpuRenderPassEncoderEnd(pass);
        c.wgpuRenderPassEncoderRelease(pass);
        const cmdbuf = c.wgpuCommandEncoderFinish(enc, null);
        defer c.wgpuCommandBufferRelease(cmdbuf);
        c.wgpuQueueSubmit(self.queue, 1, &cmdbuf);
        _ = c.wgpuSurfacePresent(self.surface);
        return true;
    }

    fn buildScene(self: *Gfx, g: *const game_mod.Game) void {
        self.count = 0;
        const half = game_mod.arena_half + 0.5;
        self.add(.{ 0, -0.1, 0 }, .{ half * 2, 0.2, half * 2 }, .{ 0.22, 0.24, 0.26, 0 });
        self.add(.{ 0, 1, -half }, .{ half * 2, 2, 0.4 }, .{ 0.35, 0.33, 0.3, 0 });
        self.add(.{ 0, 1, half }, .{ half * 2, 2, 0.4 }, .{ 0.35, 0.33, 0.3, 0 });
        self.add(.{ -half, 1, 0 }, .{ 0.4, 2, half * 2 }, .{ 0.3, 0.33, 0.35, 0 });
        self.add(.{ half, 1, 0 }, .{ 0.4, 2, half * 2 }, .{ 0.3, 0.33, 0.35, 0 });
        for (game_mod.spawn_points) |p| self.add(p + V3{ 0, 0.02, 0 }, .{ 2, 0.05, 2 }, .{ 0.1, 0.3, 0.5, 0.4 });

        for (g.enemies.items) |e| {
            const flash = e.hurt_flash > 0;
            const body: [4]f32 = if (e.sinking) .{ 0.25, 0.2, 0.15, 0 } else if (flash) .{ 1, 0.9, 0.9, 0.6 } else .{ 0.3, 0.75, 0.25, 0 };
            self.add(e.pos + V3{ 0, 0.5, 0 }, .{ 0.8, 1.0, 0.8 }, body);
            self.add(e.pos + V3{ 0, 1.2, 0 }, .{ 0.5, 0.4, 0.5 }, .{ body[0] * 0.8, body[1] * 0.8, body[2] * 0.8, body[3] });
        }

        for (g.effects[0..g.effect_count]) |fx| {
            const s: f32 = switch (fx.id) {
                T.Fx.hit => 0.15 + fx.ttl,
                T.Fx.death => 0.3 + fx.ttl * 2,
                else => 0.2 + fx.ttl * 3,
            };
            const col: [4]f32 = switch (fx.id) {
                T.Fx.hit => .{ 1, 0.85, 0.2, 1 },
                T.Fx.death => .{ 1, 0.35, 0.1, 1 },
                else => .{ 0.3, 0.7, 1, 1 },
            };
            self.add(fx.pos, .{ s, s, s }, col);
        }

        // crosshair and muzzle flash, placed in front of the eye
        const fwd = g.player.forward();
        const eye = g.player.eye();
        self.add(eye + fwd * splat(2), .{ 0.02, 0.02, 0.02 }, .{ 1, 1, 1, 1 });
        if (g.muzzle_flash > 0) self.add(eye + fwd * splat(0.6) + V3{ 0, -0.15, 0 }, .{ 0.08, 0.08, 0.08 }, .{ 1, 0.9, 0.5, 1 });
    }

    fn add(self: *Gfx, center: V3, scale: V3, color: [4]f32) void {
        if (self.count == max_instances) return;
        self.instances[self.count] = .{ .center = .{ center[0], center[1], center[2], 0 }, .scale = .{ scale[0], scale[1], scale[2], 0 }, .color = color };
        self.count += 1;
    }

    fn buffer(self: *Gfx, label: []const u8, size: u64, usage: c.WGPUBufferUsage) c.WGPUBuffer {
        var d = std.mem.zeroes(c.WGPUBufferDescriptor);
        d.label = sv(label);
        d.size = size;
        d.usage = usage;
        return c.wgpuDeviceCreateBuffer(self.device, &d);
    }

    fn createPipeline(self: *Gfx) !void {
        var wgsl = std.mem.zeroes(c.WGPUShaderSourceWGSL);
        wgsl.chain.sType = c.WGPUSType_ShaderSourceWGSL;
        wgsl.code = sv(shader_src);
        var smd = std.mem.zeroes(c.WGPUShaderModuleDescriptor);
        smd.nextInChain = &wgsl.chain;
        smd.label = sv("cubes");
        const module = c.wgpuDeviceCreateShaderModule(self.device, &smd) orelse return error.WgpuShader;
        defer c.wgpuShaderModuleRelease(module);

        var bgl_entry = std.mem.zeroes(c.WGPUBindGroupLayoutEntry);
        bgl_entry.binding = 0;
        bgl_entry.visibility = c.WGPUShaderStage_Vertex | c.WGPUShaderStage_Fragment;
        bgl_entry.buffer.type = c.WGPUBufferBindingType_Uniform;
        bgl_entry.buffer.minBindingSize = @sizeOf(Globals);
        var bgld = std.mem.zeroes(c.WGPUBindGroupLayoutDescriptor);
        bgld.entryCount = 1;
        bgld.entries = &bgl_entry;
        const bgl = c.wgpuDeviceCreateBindGroupLayout(self.device, &bgld);
        defer c.wgpuBindGroupLayoutRelease(bgl);

        var bg_entry = std.mem.zeroes(c.WGPUBindGroupEntry);
        bg_entry.binding = 0;
        bg_entry.buffer = self.globals_buf;
        bg_entry.size = @sizeOf(Globals);
        var bgd = std.mem.zeroes(c.WGPUBindGroupDescriptor);
        bgd.layout = bgl;
        bgd.entryCount = 1;
        bgd.entries = &bg_entry;
        self.bind_group = c.wgpuDeviceCreateBindGroup(self.device, &bgd);

        var pld = std.mem.zeroes(c.WGPUPipelineLayoutDescriptor);
        pld.bindGroupLayoutCount = 1;
        pld.bindGroupLayouts = &bgl;
        const layout = c.wgpuDeviceCreatePipelineLayout(self.device, &pld);
        defer c.wgpuPipelineLayoutRelease(layout);

        const vattrs = [_]c.WGPUVertexAttribute{
            attr(c.WGPUVertexFormat_Float32x3, 0, 0),
            attr(c.WGPUVertexFormat_Float32x3, 12, 1),
        };
        const iattrs = [_]c.WGPUVertexAttribute{
            attr(c.WGPUVertexFormat_Float32x4, 0, 2),
            attr(c.WGPUVertexFormat_Float32x4, 16, 3),
            attr(c.WGPUVertexFormat_Float32x4, 32, 4),
        };
        var layouts = [2]c.WGPUVertexBufferLayout{ std.mem.zeroes(c.WGPUVertexBufferLayout), std.mem.zeroes(c.WGPUVertexBufferLayout) };
        layouts[0].stepMode = c.WGPUVertexStepMode_Vertex;
        layouts[0].arrayStride = @sizeOf(Vertex);
        layouts[0].attributeCount = vattrs.len;
        layouts[0].attributes = &vattrs;
        layouts[1].stepMode = c.WGPUVertexStepMode_Instance;
        layouts[1].arrayStride = @sizeOf(Instance);
        layouts[1].attributeCount = iattrs.len;
        layouts[1].attributes = &iattrs;

        var target = std.mem.zeroes(c.WGPUColorTargetState);
        target.format = self.format;
        target.writeMask = c.WGPUColorWriteMask_All;
        var frag = std.mem.zeroes(c.WGPUFragmentState);
        frag.module = module;
        frag.entryPoint = sv("fs");
        frag.targetCount = 1;
        frag.targets = &target;

        var ds = std.mem.zeroes(c.WGPUDepthStencilState);
        ds.format = depth_format;
        ds.depthWriteEnabled = c.WGPUOptionalBool_True;
        ds.depthCompare = c.WGPUCompareFunction_Less;
        ds.stencilFront.compare = c.WGPUCompareFunction_Always;
        ds.stencilBack.compare = c.WGPUCompareFunction_Always;

        var pd = std.mem.zeroes(c.WGPURenderPipelineDescriptor);
        pd.label = sv("cubes");
        pd.layout = layout;
        pd.vertex.module = module;
        pd.vertex.entryPoint = sv("vs");
        pd.vertex.bufferCount = layouts.len;
        pd.vertex.buffers = &layouts;
        pd.primitive.topology = c.WGPUPrimitiveTopology_TriangleList;
        pd.primitive.frontFace = c.WGPUFrontFace_CCW;
        pd.primitive.cullMode = c.WGPUCullMode_Back;
        pd.depthStencil = &ds;
        pd.multisample.count = 1;
        pd.multisample.mask = 0xFFFF_FFFF;
        pd.fragment = &frag;
        self.pipeline = c.wgpuDeviceCreateRenderPipeline(self.device, &pd) orelse return error.WgpuPipeline;
    }
};

fn createSurface(instance: c.WGPUInstance, window: *c.SDL_Window) !c.WGPUSurface {
    const props = c.SDL_GetWindowProperties(window);
    var sd = std.mem.zeroes(c.WGPUSurfaceDescriptor);
    sd.label = sv("window");
    const driver = std.mem.span(c.SDL_GetCurrentVideoDriver() orelse return error.NoVideoDriver);
    if (std.mem.eql(u8, driver, "wayland")) {
        var src = std.mem.zeroes(c.WGPUSurfaceSourceWaylandSurface);
        src.chain.sType = c.WGPUSType_SurfaceSourceWaylandSurface;
        src.display = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
        src.surface = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
        sd.nextInChain = &src.chain;
        return c.wgpuInstanceCreateSurface(instance, &sd) orelse error.WgpuSurface;
    } else if (std.mem.eql(u8, driver, "x11")) {
        var src = std.mem.zeroes(c.WGPUSurfaceSourceXlibWindow);
        src.chain.sType = c.WGPUSType_SurfaceSourceXlibWindow;
        src.display = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
        src.window = @intCast(c.SDL_GetNumberProperty(props, c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0));
        sd.nextInChain = &src.chain;
        return c.wgpuInstanceCreateSurface(instance, &sd) orelse error.WgpuSurface;
    } else if (std.mem.eql(u8, driver, "windows")) {
        var src = std.mem.zeroes(c.WGPUSurfaceSourceWindowsHWND);
        src.chain.sType = c.WGPUSType_SurfaceSourceWindowsHWND;
        src.hinstance = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER, null);
        src.hwnd = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
        sd.nextInChain = &src.chain;
        return c.wgpuInstanceCreateSurface(instance, &sd) orelse error.WgpuSurface;
    }
    std.log.err("unsupported SDL video driver for wgpu: {s}", .{driver});
    return error.UnsupportedVideoDriver;
}

fn Request(comptime H: type) type {
    return struct { done: bool = false, value: H = null };
}

fn onAdapter(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, msg: c.WGPUStringView, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const req: *Request(c.WGPUAdapter) = @ptrCast(@alignCast(ud1.?));
    if (status == c.WGPURequestAdapterStatus_Success) req.value = adapter else std.log.err("wgpu adapter: {s}", .{viewSlice(msg)});
    req.done = true;
}

fn onDevice(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, msg: c.WGPUStringView, ud1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const req: *Request(c.WGPUDevice) = @ptrCast(@alignCast(ud1.?));
    if (status == c.WGPURequestDeviceStatus_Success) req.value = device else std.log.err("wgpu device: {s}", .{viewSlice(msg)});
    req.done = true;
}

fn onDeviceError(_: [*c]const c.WGPUDevice, kind: c.WGPUErrorType, msg: c.WGPUStringView, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    std.log.err("wgpu error {d}: {s}", .{ kind, viewSlice(msg) });
}

fn sv(s: []const u8) c.WGPUStringView {
    return .{ .data = s.ptr, .length = s.len };
}

fn viewSlice(v: c.WGPUStringView) []const u8 {
    const p = v.data orelse return "";
    if (v.length == std.math.maxInt(usize)) return std.mem.span(@as([*:0]const u8, @ptrCast(p)));
    return p[0..v.length];
}

fn attr(format: c.WGPUVertexFormat, offset: u64, location: u32) c.WGPUVertexAttribute {
    var a = std.mem.zeroes(c.WGPUVertexAttribute);
    a.format = format;
    a.offset = offset;
    a.shaderLocation = location;
    return a;
}

fn splat(x: f32) V3 {
    return @splat(x);
}

// ---- math (column-major, WebGPU clip space z in [0, 1]) ----

pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const f = 1.0 / @tan(fovy / 2);
    var m = std.mem.zeroes([16]f32);
    m[0] = f / aspect;
    m[5] = f;
    m[10] = far / (near - far);
    m[11] = -1;
    m[14] = near * far / (near - far);
    return m;
}

pub fn lookAt(eye: V3, center: V3, up: V3) [16]f32 {
    const f = normalize(center - eye);
    const s = normalize(cross(f, up));
    const u = cross(s, f);
    return .{
        s[0], u[0], -f[0], 0,
        s[1], u[1], -f[1], 0,
        s[2], u[2], -f[2], 0,
        -dot(s, eye), -dot(u, eye), dot(f, eye), 1,
    };
}

pub fn mul(a: [16]f32, b: [16]f32) [16]f32 {
    var r: [16]f32 = undefined;
    for (0..4) |col| for (0..4) |row| {
        var acc: f32 = 0;
        for (0..4) |k| acc += a[k * 4 + row] * b[col * 4 + k];
        r[col * 4 + row] = acc;
    };
    return r;
}

fn dot(a: V3, b: V3) f32 {
    return @reduce(.Add, a * b);
}

fn cross(a: V3, b: V3) V3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn normalize(v: V3) V3 {
    return v / splat(@sqrt(dot(v, v)));
}

// Unit cube centered at the origin, 6 faces x 2 triangles, CCW from outside.
const cube_vertices = blk: {
    const faces = [_]struct { n: [3]f32, u: [3]f32, v: [3]f32 }{
        .{ .n = .{ 1, 0, 0 }, .u = .{ 0, 0, -1 }, .v = .{ 0, 1, 0 } },
        .{ .n = .{ -1, 0, 0 }, .u = .{ 0, 0, 1 }, .v = .{ 0, 1, 0 } },
        .{ .n = .{ 0, 1, 0 }, .u = .{ 1, 0, 0 }, .v = .{ 0, 0, -1 } },
        .{ .n = .{ 0, -1, 0 }, .u = .{ 1, 0, 0 }, .v = .{ 0, 0, 1 } },
        .{ .n = .{ 0, 0, 1 }, .u = .{ 1, 0, 0 }, .v = .{ 0, 1, 0 } },
        .{ .n = .{ 0, 0, -1 }, .u = .{ -1, 0, 0 }, .v = .{ 0, 1, 0 } },
    };
    const corners = [_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, -1 }, .{ 1, 1 }, .{ -1, 1 } };
    var out: [36]Vertex = undefined;
    for (faces, 0..) |f, fi| {
        for (corners, 0..) |cc, ci| {
            var p: [3]f32 = undefined;
            for (0..3) |k| p[k] = 0.5 * (f.n[k] + cc[0] * f.u[k] + cc[1] * f.v[k]);
            out[fi * 6 + ci] = .{ .pos = p, .normal = f.n };
        }
    }
    break :blk out;
};

test "perspective * lookAt maps a point straight ahead to the screen center" {
    const vp = mul(perspective(1.2, 1.5, 0.1, 100), lookAt(.{ 0, 1.6, 0 }, .{ 0, 1.6, -1 }, .{ 0, 1, 0 }));
    const p = [4]f32{ 0, 1.6, -10, 1 };
    var clip: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..4) |row| for (0..4) |k| {
        clip[row] += vp[k * 4 + row] * p[k];
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0), clip[0] / clip[3], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), clip[1] / clip[3], 1e-5);
    const z = clip[2] / clip[3];
    try std.testing.expect(z > 0 and z < 1);
}

//! Optional OpenXR: the loader is opened at runtime, so the game runs without it.
//! wgpu-native exposes no Vulkan interop, so XR cannot submit stereo frames here. When the runtime offers
//! XR_MND_headless, a session supplies head orientation (drives aim) and a controller trigger (fires);
//! the picture stays on the desktop window. Without a loader, runtime or HMD, `init` returns null.
const std = @import("std");
const c = @import("c");
const input = @import("input.zig");

const loader_names: []const [*:0]const u8 = switch (@import("builtin").os.tag) {
    .windows => &.{"openxr_loader.dll"},
    else => &.{ "libopenxr_loader.so.1", "libopenxr_loader.so" },
};

fn makeVersion(major: u64, minor: u64, patch: u64) u64 {
    return (major << 48) | (minor << 32) | patch;
}

pub const Pose = struct { yaw: f32, pitch: f32 };

pub const Xr = struct {
    lib: *c.SDL_SharedObject,
    gipa: c.PFN_xrGetInstanceProcAddr,
    instance: c.XrInstance,
    system: c.XrSystemId,
    runtime_name: [c.XR_MAX_RUNTIME_NAME_SIZE]u8 = std.mem.zeroes([c.XR_MAX_RUNTIME_NAME_SIZE]u8),
    system_name: [c.XR_MAX_SYSTEM_NAME_SIZE]u8 = std.mem.zeroes([c.XR_MAX_SYSTEM_NAME_SIZE]u8),
    headless: bool = false,

    session: c.XrSession = null,
    running: bool = false,
    local: c.XrSpace = null,
    view: c.XrSpace = null,
    action_set: c.XrActionSet = null,
    fire: c.XrAction = null,
    pose: ?Pose = null,
    trigger: bool = false,

    // instance-level functions
    destroyInstance: c.PFN_xrDestroyInstance = null,
    pollEvent: c.PFN_xrPollEvent = null,
    createSession: c.PFN_xrCreateSession = null,
    destroySession: c.PFN_xrDestroySession = null,
    beginSession: c.PFN_xrBeginSession = null,
    endSession: c.PFN_xrEndSession = null,
    createReferenceSpace: c.PFN_xrCreateReferenceSpace = null,
    destroySpace: c.PFN_xrDestroySpace = null,
    locateSpace: c.PFN_xrLocateSpace = null,
    waitFrame: c.PFN_xrWaitFrame = null,
    beginFrame: c.PFN_xrBeginFrame = null,
    endFrame: c.PFN_xrEndFrame = null,
    stringToPath: c.PFN_xrStringToPath = null,
    createActionSet: c.PFN_xrCreateActionSet = null,
    createAction: c.PFN_xrCreateAction = null,
    suggestBindings: c.PFN_xrSuggestInteractionProfileBindings = null,
    attachActionSets: c.PFN_xrAttachSessionActionSets = null,
    syncActions: c.PFN_xrSyncActions = null,
    getActionStateBoolean: c.PFN_xrGetActionStateBoolean = null,

    pub fn init(gpa: std.mem.Allocator) ?*Xr {
        const lib = for (loader_names) |name| {
            if (c.SDL_LoadObject(name)) |l| break l;
        } else {
            std.log.info("OpenXR loader not found: desktop mode", .{});
            return null;
        };
        const gipa: c.PFN_xrGetInstanceProcAddr = @ptrCast(c.SDL_LoadFunction(lib, "xrGetInstanceProcAddr") orelse {
            c.SDL_UnloadObject(lib);
            return null;
        });
        const self = gpa.create(Xr) catch return null;
        self.* = .{ .lib = lib, .gipa = gipa, .instance = null, .system = c.XR_NULL_SYSTEM_ID };
        self.start() catch |err| {
            std.log.info("OpenXR unavailable ({s}): desktop mode", .{@errorName(err)});
            self.deinit(gpa);
            return null;
        };
        return self;
    }

    pub fn deinit(self: *Xr, gpa: std.mem.Allocator) void {
        if (self.local) |s| _ = self.destroySpace.?(s);
        if (self.view) |s| _ = self.destroySpace.?(s);
        if (self.session) |s| _ = self.destroySession.?(s);
        if (self.instance) |i| if (self.destroyInstance) |f| {
            _ = f(i);
        };
        c.SDL_UnloadObject(self.lib);
        gpa.destroy(self);
    }

    pub fn runtimeName(self: *const Xr) []const u8 {
        return std.mem.sliceTo(&self.runtime_name, 0);
    }

    pub fn systemName(self: *const Xr) []const u8 {
        return std.mem.sliceTo(&self.system_name, 0);
    }

    fn global(self: *Xr, comptime F: type, name: [*:0]const u8) !F {
        var f: c.PFN_xrVoidFunction = null;
        try check(self.gipa.?(self.instance, name, &f));
        return @ptrCast(f orelse return error.MissingFunction);
    }

    fn start(self: *Xr) !void {
        const enumExt = try self.global(c.PFN_xrEnumerateInstanceExtensionProperties, "xrEnumerateInstanceExtensionProperties");
        var ext_count: u32 = 0;
        try check(enumExt.?(null, 0, &ext_count, null));
        var props: [256]c.XrExtensionProperties = undefined;
        ext_count = @min(ext_count, props.len);
        for (props[0..ext_count]) |*p| p.* = .{ .type = c.XR_TYPE_EXTENSION_PROPERTIES, .next = null, .extensionName = undefined, .extensionVersion = 0 };
        try check(enumExt.?(null, ext_count, &ext_count, &props));
        for (props[0..ext_count]) |p| {
            if (std.mem.eql(u8, std.mem.sliceTo(&p.extensionName, 0), c.XR_MND_HEADLESS_EXTENSION_NAME)) self.headless = true;
        }

        var ci = std.mem.zeroes(c.XrInstanceCreateInfo);
        ci.type = c.XR_TYPE_INSTANCE_CREATE_INFO;
        copyName(&ci.applicationInfo.applicationName, "Starcraft Base Defense");
        copyName(&ci.applicationInfo.engineName, "sbd_native");
        ci.applicationInfo.applicationVersion = 1;
        ci.applicationInfo.engineVersion = 1;
        ci.applicationInfo.apiVersion = makeVersion(1, 0, 0);
        const exts = [_][*:0]const u8{c.XR_MND_HEADLESS_EXTENSION_NAME};
        if (self.headless) {
            ci.enabledExtensionCount = 1;
            ci.enabledExtensionNames = @ptrCast(&exts);
        }
        const createInstance = try self.global(c.PFN_xrCreateInstance, "xrCreateInstance");
        try check(createInstance.?(&ci, &self.instance));

        self.destroyInstance = try self.global(c.PFN_xrDestroyInstance, "xrDestroyInstance");
        const getProps = try self.global(c.PFN_xrGetInstanceProperties, "xrGetInstanceProperties");
        var ip = std.mem.zeroes(c.XrInstanceProperties);
        ip.type = c.XR_TYPE_INSTANCE_PROPERTIES;
        if (getProps.?(self.instance, &ip) == c.XR_SUCCESS) @memcpy(&self.runtime_name, &ip.runtimeName);

        const getSystem = try self.global(c.PFN_xrGetSystem, "xrGetSystem");
        var gi = std.mem.zeroes(c.XrSystemGetInfo);
        gi.type = c.XR_TYPE_SYSTEM_GET_INFO;
        gi.formFactor = c.XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
        try check(getSystem.?(self.instance, &gi, &self.system));
        const getSysProps = try self.global(c.PFN_xrGetSystemProperties, "xrGetSystemProperties");
        var sp = std.mem.zeroes(c.XrSystemProperties);
        sp.type = c.XR_TYPE_SYSTEM_PROPERTIES;
        if (getSysProps.?(self.instance, self.system, &sp) == c.XR_SUCCESS) @memcpy(&self.system_name, &sp.systemName);

        inline for (.{
            .{ "pollEvent", "xrPollEvent" },                    .{ "createSession", "xrCreateSession" },
            .{ "destroySession", "xrDestroySession" },          .{ "beginSession", "xrBeginSession" },
            .{ "endSession", "xrEndSession" },                  .{ "createReferenceSpace", "xrCreateReferenceSpace" },
            .{ "destroySpace", "xrDestroySpace" },              .{ "locateSpace", "xrLocateSpace" },
            .{ "waitFrame", "xrWaitFrame" },                    .{ "beginFrame", "xrBeginFrame" },
            .{ "endFrame", "xrEndFrame" },                      .{ "stringToPath", "xrStringToPath" },
            .{ "createActionSet", "xrCreateActionSet" },        .{ "createAction", "xrCreateAction" },
            .{ "suggestBindings", "xrSuggestInteractionProfileBindings" },
            .{ "attachActionSets", "xrAttachSessionActionSets" }, .{ "syncActions", "xrSyncActions" },
            .{ "getActionStateBoolean", "xrGetActionStateBoolean" },
        }) |e| {
            @field(self, e[0]) = try self.global(@FieldType(Xr, e[0]), e[1]);
        }

        if (!self.headless) return; // instance + system only: reported, but no session without graphics interop
        try self.createInput();
        var sci = std.mem.zeroes(c.XrSessionCreateInfo);
        sci.type = c.XR_TYPE_SESSION_CREATE_INFO;
        sci.systemId = self.system;
        try check(self.createSession.?(self.instance, &sci, &self.session));
        var rs = std.mem.zeroes(c.XrReferenceSpaceCreateInfo);
        rs.type = c.XR_TYPE_REFERENCE_SPACE_CREATE_INFO;
        rs.poseInReferenceSpace.orientation.w = 1;
        rs.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_LOCAL;
        try check(self.createReferenceSpace.?(self.session, &rs, &self.local));
        rs.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_VIEW;
        try check(self.createReferenceSpace.?(self.session, &rs, &self.view));
        var ai = std.mem.zeroes(c.XrSessionActionSetsAttachInfo);
        ai.type = c.XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO;
        ai.countActionSets = 1;
        ai.actionSets = &self.action_set;
        try check(self.attachActionSets.?(self.session, &ai));
    }

    fn createInput(self: *Xr) !void {
        var asi = std.mem.zeroes(c.XrActionSetCreateInfo);
        asi.type = c.XR_TYPE_ACTION_SET_CREATE_INFO;
        copyName(&asi.actionSetName, "gameplay");
        copyName(&asi.localizedActionSetName, "Gameplay");
        try check(self.createActionSet.?(self.instance, &asi, &self.action_set));
        var aci = std.mem.zeroes(c.XrActionCreateInfo);
        aci.type = c.XR_TYPE_ACTION_CREATE_INFO;
        aci.actionType = c.XR_ACTION_TYPE_BOOLEAN_INPUT;
        copyName(&aci.actionName, "fire");
        copyName(&aci.localizedActionName, "Fire");
        try check(self.createAction.?(self.action_set, &aci, &self.fire));

        const profiles = [_][2][*:0]const u8{
            .{ "/interaction_profiles/khr/simple_controller", "/user/hand/right/input/select/click" },
            .{ "/interaction_profiles/oculus/touch_controller", "/user/hand/right/input/trigger/value" },
            .{ "/interaction_profiles/valve/index_controller", "/user/hand/right/input/trigger/click" },
            .{ "/interaction_profiles/htc/vive_controller", "/user/hand/right/input/trigger/click" },
        };
        for (profiles) |p| {
            var profile: c.XrPath = 0;
            var binding: c.XrActionSuggestedBinding = .{ .action = self.fire, .binding = 0 };
            if (self.stringToPath.?(self.instance, p[0], &profile) != c.XR_SUCCESS) continue;
            if (self.stringToPath.?(self.instance, p[1], &binding.binding) != c.XR_SUCCESS) continue;
            var sb = std.mem.zeroes(c.XrInteractionProfileSuggestedBinding);
            sb.type = c.XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING;
            sb.interactionProfile = profile;
            sb.countSuggestedBindings = 1;
            sb.suggestedBindings = &binding;
            _ = self.suggestBindings.?(self.instance, &sb); // a runtime may reject profiles it does not know
        }
    }

    /// Pumps runtime events and, while the session runs, reads head pose and trigger.
    /// Returns false when the runtime asks the app to exit.
    pub fn update(self: *Xr) bool {
        var ev: c.XrEventDataBuffer = undefined;
        while (true) {
            ev.type = c.XR_TYPE_EVENT_DATA_BUFFER;
            ev.next = null;
            if (self.pollEvent.?(self.instance, &ev) != c.XR_SUCCESS) break;
            switch (ev.type) {
                c.XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING => return false,
                c.XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED => {
                    const sc: *const c.XrEventDataSessionStateChanged = @ptrCast(&ev);
                    switch (sc.state) {
                        c.XR_SESSION_STATE_READY => {
                            var bi = std.mem.zeroes(c.XrSessionBeginInfo);
                            bi.type = c.XR_TYPE_SESSION_BEGIN_INFO;
                            bi.primaryViewConfigurationType = c.XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
                            self.running = self.beginSession.?(self.session, &bi) == c.XR_SUCCESS;
                        },
                        c.XR_SESSION_STATE_STOPPING => {
                            _ = self.endSession.?(self.session);
                            self.running = false;
                            self.pose = null;
                        },
                        c.XR_SESSION_STATE_EXITING, c.XR_SESSION_STATE_LOSS_PENDING => return false,
                        else => {},
                    }
                },
                else => {},
            }
        }
        if (!self.running) return true;

        var fs = std.mem.zeroes(c.XrFrameState);
        fs.type = c.XR_TYPE_FRAME_STATE;
        var wi = std.mem.zeroes(c.XrFrameWaitInfo);
        wi.type = c.XR_TYPE_FRAME_WAIT_INFO;
        if (self.waitFrame.?(self.session, &wi, &fs) != c.XR_SUCCESS) return true;
        var bi = std.mem.zeroes(c.XrFrameBeginInfo);
        bi.type = c.XR_TYPE_FRAME_BEGIN_INFO;
        _ = self.beginFrame.?(self.session, &bi);

        var active: c.XrActiveActionSet = .{ .actionSet = self.action_set, .subactionPath = 0 };
        var si = std.mem.zeroes(c.XrActionsSyncInfo);
        si.type = c.XR_TYPE_ACTIONS_SYNC_INFO;
        si.countActiveActionSets = 1;
        si.activeActionSets = &active;
        if (self.syncActions.?(self.session, &si) == c.XR_SUCCESS) {
            var gi = std.mem.zeroes(c.XrActionStateGetInfo);
            gi.type = c.XR_TYPE_ACTION_STATE_GET_INFO;
            gi.action = self.fire;
            var st = std.mem.zeroes(c.XrActionStateBoolean);
            st.type = c.XR_TYPE_ACTION_STATE_BOOLEAN;
            if (self.getActionStateBoolean.?(self.session, &gi, &st) == c.XR_SUCCESS)
                self.trigger = st.isActive != 0 and st.currentState != 0;
        }

        var loc = std.mem.zeroes(c.XrSpaceLocation);
        loc.type = c.XR_TYPE_SPACE_LOCATION;
        if (self.locateSpace.?(self.view, self.local, fs.predictedDisplayTime, &loc) == c.XR_SUCCESS and
            loc.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT != 0)
        {
            self.pose = poseFromQuat(loc.pose.orientation);
        }

        var ei = std.mem.zeroes(c.XrFrameEndInfo);
        ei.type = c.XR_TYPE_FRAME_END_INFO;
        ei.displayTime = fs.predictedDisplayTime;
        ei.environmentBlendMode = c.XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
        _ = self.endFrame.?(self.session, &ei); // headless: no layers
        return true;
    }

    /// Feeds XR input into the shared action state (trigger -> fire).
    pub fn applyInput(self: *const Xr, state: *input.State) void {
        state.trigger = self.trigger;
    }
};

/// OpenXR view space looks down -Z with +Y up, like the game camera.
pub fn poseFromQuat(q: c.XrQuaternionf) Pose {
    const x = q.x;
    const y = q.y;
    const z = q.z;
    const w = q.w;
    // forward = rotate (0, 0, -1)
    const fx = -(2 * (x * z + w * y));
    const fy = -(2 * (y * z - w * x));
    const fz = -(1 - 2 * (x * x + y * y));
    return .{ .yaw = std.math.atan2(fx, -fz), .pitch = std.math.atan2(fy, @sqrt(fx * fx + fz * fz)) };
}

fn copyName(dst: anytype, src: []const u8) void {
    @memset(dst, 0);
    @memcpy(dst[0..src.len], src);
}

fn check(r: c.XrResult) !void {
    if (r < 0) {
        std.log.debug("OpenXR call failed: {d}", .{r});
        return error.OpenXrCallFailed;
    }
}

test "head pose from quaternion: identity looks ahead, yaw right is positive" {
    const id = poseFromQuat(.{ .x = 0, .y = 0, .z = 0, .w = 1 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), id.yaw, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), id.pitch, 1e-6);
    // rotating -90 deg about +Y turns the view to +X (right)
    const s = @sin(-std.math.pi / 4.0);
    const right = poseFromQuat(.{ .x = 0, .y = s, .z = 0, .w = @cos(-std.math.pi / 4.0) });
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), right.yaw, 1e-5);
}

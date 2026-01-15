const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Option to build without NVML (for development/testing)
    const use_nvml = b.option(bool, "nvml", "Link against NVML (requires NVIDIA driver)") orelse true;

    // Import nvprime - the unified NVIDIA platform
    const nvprime_dep = b.dependency("nvprime", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the venom module with nvprime integration
    const mod = b.addModule("venom", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nvprime", .module = nvprime_dep.module("nvprime") },
        },
    });

    // Link NVML for GPU queries
    if (use_nvml) {
        mod.linkSystemLibrary("nvidia-ml", .{});
        mod.linkSystemLibrary("c", .{});
        mod.addIncludePath(.{ .cwd_relative = "/opt/cuda/targets/x86_64-linux/include" });
    }

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "venom",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "venom", .module = mod },
                .{ .name = "nvprime", .module = nvprime_dep.module("nvprime") },
            },
        }),
    });

    // Link NVML for CLI
    if (use_nvml) {
        exe.root_module.linkSystemLibrary("nvidia-ml", .{});
        exe.root_module.linkSystemLibrary("c", .{});
        exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/cuda/targets/x86_64-linux/include" });
    }

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // Build the Vulkan layer shared library (libvenom_layer.so)
    // This is an implicit Vulkan layer that hooks game frame timing
    const layer_module = b.createModule(.{
        .root_source_file = b.path("src/vulkan_layer_exports.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nvprime", .module = nvprime_dep.module("nvprime") },
        },
    });
    layer_module.linkSystemLibrary("c", .{});

    const layer_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "venom_layer",
        .root_module = layer_module,
    });

    b.installArtifact(layer_lib);

    // Install the layer manifest
    b.installFile("layer/VK_LAYER_VENOM_performance.json", "share/vulkan/implicit_layer.d/VK_LAYER_VENOM_performance.json");

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}

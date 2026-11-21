using System.IO;
using UnrealBuildTool;

// External module: links the Zig core (core/zig-out, produced by core/build.sh) and exposes core/include/sbd.h.
public class SbdCore : ModuleRules
{
	public SbdCore(ReadOnlyTargetRules Target) : base(Target)
	{
		Type = ModuleType.External;

		// engines/unreal/StarcraftBaseDefense/Source/ThirdParty/SbdCore -> repository root is 6 levels up.
		string CoreDir = Path.GetFullPath(Path.Combine(ModuleDirectory, "../../../../../../core"));
		string OutDir = Path.Combine(CoreDir, "zig-out");

		PublicSystemIncludePaths.Add(Path.Combine(CoreDir, "include"));

		if (Target.Platform == UnrealTargetPlatform.Win64)
		{
			string Dir = Path.Combine(OutDir, "x86_64-windows");
			PublicAdditionalLibraries.Add(Path.Combine(Dir, "sbd_core.lib"));
			PublicDelayLoadDLLs.Add("sbd_core.dll");
			RuntimeDependencies.Add("$(BinaryOutputDir)/sbd_core.dll", Path.Combine(Dir, "sbd_core.dll"));
		}
		else if (Target.Platform == UnrealTargetPlatform.Linux)
		{
			string Lib = Path.Combine(OutDir, "x86_64-linux", "libsbd_core.so");
			PublicAdditionalLibraries.Add(Lib);
			RuntimeDependencies.Add("$(BinaryOutputDir)/libsbd_core.so", Lib);
		}
		else if (Target.Platform == UnrealTargetPlatform.Android)
		{
			// Quest / Android arm64. Packaging of the .so is handled by the Android UPL of the game module.
			PublicAdditionalLibraries.Add(Path.Combine(OutDir, "aarch64-android", "libsbd_core.so"));
		}
	}
}

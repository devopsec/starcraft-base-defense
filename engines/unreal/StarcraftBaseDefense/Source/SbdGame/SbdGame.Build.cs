using UnrealBuildTool;

public class SbdGame : ModuleRules
{
	public SbdGame(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "AIModule", "NavigationSystem",
			"Niagara", "Json", "JsonUtilities", "SbdCore"
		});
	}
}

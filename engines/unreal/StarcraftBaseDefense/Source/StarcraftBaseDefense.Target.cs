using UnrealBuildTool;

public class StarcraftBaseDefenseTarget : TargetRules
{
	public StarcraftBaseDefenseTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("SbdGame");
	}
}

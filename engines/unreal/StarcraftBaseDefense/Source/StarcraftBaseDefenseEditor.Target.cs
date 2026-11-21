using UnrealBuildTool;

public class StarcraftBaseDefenseEditorTarget : TargetRules
{
	public StarcraftBaseDefenseEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("SbdGame");
	}
}

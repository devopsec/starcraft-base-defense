#pragma once

#include "CoreMinimal.h"
#include "GameFramework/HUD.h"
#include "SbdHud.generated.h"

/** Canvas HUD: score, high score, health, enemies and the pause/game-over banner. */
UCLASS()
class SBDGAME_API ASbdHud : public AHUD
{
	GENERATED_BODY()

public:
	virtual void DrawHUD() override;
};

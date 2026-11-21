#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "SbdSaveGame.generated.h"

/** Stores the core's versioned save bytes (SaveV1) verbatim; the core validates them on load. */
UCLASS()
class SBDGAME_API USbdSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	UPROPERTY()
	TArray<uint8> Bytes;
};

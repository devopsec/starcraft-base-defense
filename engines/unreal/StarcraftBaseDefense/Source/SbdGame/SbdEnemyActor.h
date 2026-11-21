#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "SbdEnemyActor.generated.h"

class ASbdGameMode;
class UStaticMeshComponent;

/** View of one core enemy. The core owns health, damage, score and despawn. */
UCLASS()
class SBDGAME_API ASbdEnemyActor : public ACharacter
{
	GENERATED_BODY()

public:
	ASbdEnemyActor();

	void Init(uint32 InEntity, ASbdGameMode* InMode, AActor* InTarget, float InSinkSpeed);
	void OnDied();

	uint32 GetEntity() const { return Entity; }

	virtual void Tick(float DeltaSeconds) override;

	UPROPERTY(EditAnywhere, Category = "Sbd")
	float AttackRange = 150.f;

private:
	UPROPERTY(VisibleAnywhere)
	TObjectPtr<UStaticMeshComponent> Body;

	uint32 Entity = 0;
	TWeakObjectPtr<ASbdGameMode> Mode;
	TWeakObjectPtr<AActor> Target;
	float SinkSpeed = 250.f;
	bool bDead = false;
	bool bInRange = false;
};

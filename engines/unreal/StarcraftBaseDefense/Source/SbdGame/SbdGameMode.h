#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "SbdAbiCheck.h"
#include "SbdGameMode.generated.h"

class ASbdEnemyActor;
class ASbdPlayerPawn;
class UNiagaraSystem;

/**
 * Owns the Zig core world. Each frame: commands in, one tick (enemy ranges via ParallelFor), events out.
 * Nothing else mutates game state; actors only send commands and react to events.
 */
UCLASS()
class SBDGAME_API ASbdGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ASbdGameMode();

	virtual void StartPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type Reason) override;
	virtual void Tick(float DeltaSeconds) override;

	// Commands (queued until the next tick)
	void SendEnemyInRange(uint32 Entity, bool bInRange);
	void SendSimple(uint32 Kind);
	void SendRestartIfGameOver();

	// HUD / view queries
	bool IsPlaying() const { return World && sbd_world_state(World) == SBD_STATE_PLAYING; }
	int32 GetScore() const { return World ? sbd_world_score(World) : 0; }
	int32 GetHighScore() const { return World ? sbd_world_high_score(World) : 0; }
	int32 GetPlayerHealth() const { return World ? sbd_world_player_health(World) : 0; }
	int32 GetEnemiesAlive() const { return EnemiesAlive; }
	FString GetBannerText() const { return Banner; }
	float GetHurtFlash() const { return HurtFlash; }

	UPROPERTY(EditAnywhere, Category = "Sbd")
	TSubclassOf<ASbdEnemyActor> EnemyClass;

	/** Effect IDs (SBD_FX_*) -> Niagara systems. Unset IDs fall back to a debug marker. */
	UPROPERTY(EditAnywhere, Category = "Sbd|Effects")
	TMap<int32, TObjectPtr<UNiagaraSystem>> EffectSystems;

private:
	void LoadConfig();
	void LoadHighScore();
	void SaveHighScore();
	void BuildArena();
	void Dispatch(const sbd_event& E);
	void SpawnView(uint32 Entity, int32 Roll);
	void OnShot(int32 Damage);
	void OnState(uint32 State);
	void PlayEffect(uint32 EffectId, const FVector& Pos);
	void StepEnemies(float Dt);

	sbd_world* World = nullptr;
	sbd_config Config{};
	TArray<sbd_cmd> Pending;
	TMap<uint32, TWeakObjectPtr<ASbdEnemyActor>> Views;
	TArray<FVector> SpawnPoints;

	int32 EnemiesAlive = 0;
	int32 HighScoreAtRunStart = 0;
	float HurtFlash = 0.f;
	FString Banner;
};

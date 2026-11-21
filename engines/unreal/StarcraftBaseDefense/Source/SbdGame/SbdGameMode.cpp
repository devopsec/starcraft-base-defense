#include "SbdGameMode.h"
#include "SbdEnemyActor.h"
#include "SbdHud.h"
#include "SbdPlayerPawn.h"
#include "SbdSaveGame.h"
#include "DrawDebugHelpers.h"
#include "Async/ParallelFor.h"
#include "Dom/JsonObject.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "NiagaraFunctionLibrary.h"
#include "NiagaraSystem.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"

namespace
{
	constexpr int32 ParallelThreshold = 32;
	constexpr int32 ChunkSize = 16;
	const TCHAR* SaveSlot = TEXT("SbdSave");

	double Num(const TSharedPtr<FJsonObject>& Root, const TCHAR* Section, const TCHAR* Key, double Fallback)
	{
		if (Root.IsValid())
		{
			const TSharedPtr<FJsonObject>* Sub = nullptr;
			if (Section && Root->TryGetObjectField(Section, Sub))
			{
				double V;
				if ((*Sub)->TryGetNumberField(Key, V)) return V;
			}
			else if (!Section)
			{
				double V;
				if (Root->TryGetNumberField(Key, V)) return V;
			}
		}
		return Fallback;
	}
}

ASbdGameMode::ASbdGameMode()
{
	PrimaryActorTick.bCanEverTick = true;
	DefaultPawnClass = ASbdPlayerPawn::StaticClass();
	HUDClass = ASbdHud::StaticClass();
	EnemyClass = ASbdEnemyActor::StaticClass();
}

void ASbdGameMode::StartPlay()
{
	Super::StartPlay();

	LoadConfig();
	World = sbd_world_create(&Config);
	if (!World)
	{
		UE_LOG(LogTemp, Error, TEXT("sbd_world_create failed"));
		return;
	}
	LoadHighScore();
	HighScoreAtRunStart = sbd_world_high_score(World);

	const float R = 1600.f; // spawn corners, centimetres
	SpawnPoints = { FVector(-R, -R, 100.f), FVector(R, -R, 100.f), FVector(R, R, 100.f), FVector(-R, R, 100.f) };
	BuildArena();
}

void ASbdGameMode::EndPlay(const EEndPlayReason::Type Reason)
{
	if (World)
	{
		SaveHighScore();
		sbd_world_destroy(World);
		World = nullptr;
	}
	Super::EndPlay(Reason);
}

void ASbdGameMode::LoadConfig()
{
	sbd_config_default(&Config);

	// data/balance.json is the single source of tunables shared by all engines.
	const FString Path = FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectDir(), TEXT("../../../data/balance.json")));
	FString Text;
	TSharedPtr<FJsonObject> Root;
	if (!FFileHelper::LoadFileToString(Text, *Path) || !FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Root))
	{
		UE_LOG(LogTemp, Warning, TEXT("balance.json not found at %s; using core defaults"), *Path);
		return;
	}

	Config.enemy_start_health = (uint32)Num(Root, TEXT("enemy"), TEXT("start_health"), Config.enemy_start_health);
	Config.enemy_score = (uint32)Num(Root, TEXT("enemy"), TEXT("score_value"), Config.enemy_score);
	Config.sink_speed = (float)Num(Root, TEXT("enemy"), TEXT("sink_speed"), Config.sink_speed);
	Config.sink_duration = (float)Num(Root, TEXT("enemy"), TEXT("sink_duration"), Config.sink_duration);
	Config.enemy_attack_damage = (uint32)Num(Root, TEXT("enemy"), TEXT("attack_damage"), Config.enemy_attack_damage);
	Config.enemy_attack_cooldown = (float)Num(Root, TEXT("enemy"), TEXT("attack_cooldown"), Config.enemy_attack_cooldown);
	Config.spawn_interval = (float)Num(Root, TEXT("spawner"), TEXT("spawn_interval"), Config.spawn_interval);
	Config.max_enemies = (uint32)Num(Root, TEXT("spawner"), TEXT("max_alive"), Config.max_enemies);
	Config.player_start_health = (uint32)Num(Root, TEXT("player"), TEXT("start_health"), Config.player_start_health);
	Config.weapon_damage = (uint32)Num(Root, TEXT("weapon"), TEXT("damage_per_shot"), Config.weapon_damage);
	Config.fire_rate = (float)Num(Root, TEXT("weapon"), TEXT("fire_rate"), Config.fire_rate);
	Config.seed = (uint32)Num(Root, nullptr, TEXT("seed"), Config.seed);
}

void ASbdGameMode::LoadHighScore()
{
	if (const USbdSaveGame* Save = Cast<USbdSaveGame>(UGameplayStatics::LoadGameFromSlot(SaveSlot, 0)))
	{
		const int32 Rc = sbd_save_read(World, Save->Bytes.GetData(), (uint32)Save->Bytes.Num());
		if (Rc != 0)
		{
			UE_LOG(LogTemp, Warning, TEXT("Ignoring unreadable save (%d)"), Rc);
		}
	}
}

void ASbdGameMode::SaveHighScore()
{
	if (!World)
	{
		return;
	}
	USbdSaveGame* Save = Cast<USbdSaveGame>(UGameplayStatics::CreateSaveGameObject(USbdSaveGame::StaticClass()));
	Save->Bytes.SetNumUninitialized(SBD_SAVE_SIZE);
	const uint32 Written = sbd_save_write(World, Save->Bytes.GetData(), (uint32)Save->Bytes.Num());
	if (Written == SBD_SAVE_SIZE)
	{
		UGameplayStatics::SaveGameToSlot(Save, SaveSlot, 0);
	}
}

void ASbdGameMode::BuildArena()
{
	UStaticMesh* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (!Cube)
	{
		return;
	}
	FActorSpawnParameters Params;
	if (AStaticMeshActor* Floor = GetWorld()->SpawnActor<AStaticMeshActor>(FVector(0.f, 0.f, -10.f), FRotator::ZeroRotator, Params))
	{
		Floor->GetStaticMeshComponent()->SetMobility(EComponentMobility::Movable);
		Floor->GetStaticMeshComponent()->SetStaticMesh(Cube);
		Floor->SetActorScale3D(FVector(40.f, 40.f, 0.2f));
	}
}

void ASbdGameMode::SendEnemyInRange(uint32 Entity, bool bInRange)
{
	sbd_cmd C{};
	C.kind = SBD_CMD_ENEMY_IN_RANGE;
	C.target = Entity;
	C.amount = bInRange ? 1 : 0;
	Pending.Add(C);
}

void ASbdGameMode::SendSimple(uint32 Kind)
{
	sbd_cmd C{};
	C.kind = Kind;
	Pending.Add(C);
}

void ASbdGameMode::SendRestartIfGameOver()
{
	if (World && sbd_world_state(World) == SBD_STATE_GAME_OVER)
	{
		SendSimple(SBD_CMD_RESTART);
	}
}

void ASbdGameMode::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!World)
	{
		return;
	}

	HurtFlash = FMath::Max(0.f, HurtFlash - DeltaSeconds * 3.f);

	ASbdPlayerPawn* Pawn = Cast<ASbdPlayerPawn>(UGameplayStatics::GetPlayerPawn(this, 0));
	if (Pawn && IsPlaying() && Pawn->WantsToFire())
	{
		sbd_cmd C{};
		C.kind = SBD_CMD_FIRE;
		const FVector M = Pawn->GetMuzzleLocation();
		C.point = { (float)M.X, (float)M.Y, (float)M.Z };
		Pending.Add(C);
	}

	if (Pending.Num() > 0)
	{
		sbd_world_push(World, Pending.GetData(), (uint32)Pending.Num());
		Pending.Reset();
	}

	sbd_world_begin(World, DeltaSeconds);
	StepEnemies(DeltaSeconds);
	sbd_world_resolve(World);

	sbd_event Buffer[128];
	uint32 N;
	while ((N = sbd_world_poll(World, Buffer, UE_ARRAY_COUNT(Buffer))) > 0)
	{
		for (uint32 i = 0; i < N; ++i)
		{
			Dispatch(Buffer[i]);
		}
	}
}

void ASbdGameMode::StepEnemies(float Dt)
{
	const uint32 Count = sbd_world_enemy_count(World);
	if ((int32)Count < ParallelThreshold)
	{
		sbd_world_step_enemies(World, 0, Count, Dt);
		return;
	}

	sbd_world* W = World;
	const int32 Chunks = ((int32)Count + ChunkSize - 1) / ChunkSize;
	ParallelFor(Chunks, [W, Count, Dt](int32 Index)
	{
		const uint32 Begin = (uint32)(Index * ChunkSize);
		sbd_world_step_enemies(W, Begin, FMath::Min(Begin + (uint32)ChunkSize, Count), Dt);
	});
}

void ASbdGameMode::Dispatch(const sbd_event& E)
{
	const FVector Pos(E.pos.x, E.pos.y, E.pos.z);
	switch (E.kind)
	{
	case SBD_EV_ENEMY_SPAWNED:
		SpawnView(E.entity, E.value);
		++EnemiesAlive;
		break;

	case SBD_EV_ENEMY_DIED:
		EnemiesAlive = FMath::Max(0, EnemiesAlive - 1);
		if (TWeakObjectPtr<ASbdEnemyActor>* V = Views.Find(E.entity))
		{
			if (V->IsValid()) V->Get()->OnDied();
		}
		break;

	case SBD_EV_ENEMY_DESPAWN:
		if (TWeakObjectPtr<ASbdEnemyActor>* V = Views.Find(E.entity))
		{
			if (V->IsValid()) V->Get()->Destroy();
			Views.Remove(E.entity);
		}
		break;

	case SBD_EV_EFFECT:
		if (E.effect_id == SBD_FX_PLAYER_HURT) HurtFlash = 1.f;
		PlayEffect(E.effect_id, Pos);
		break;

	case SBD_EV_SHOT:
		OnShot(E.value);
		break;

	case SBD_EV_STATE:
		OnState((uint32)E.value);
		break;
	}
}

void ASbdGameMode::SpawnView(uint32 Entity, int32 Roll)
{
	if (SpawnPoints.Num() == 0 || !EnemyClass)
	{
		return;
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	ASbdEnemyActor* Enemy = GetWorld()->SpawnActor<ASbdEnemyActor>(EnemyClass, SpawnPoints[Roll % SpawnPoints.Num()], FRotator::ZeroRotator, Params);
	if (Enemy)
	{
		Enemy->Init(Entity, this, UGameplayStatics::GetPlayerPawn(this, 0), Config.sink_speed);
		Views.Add(Entity, Enemy);
	}
}

void ASbdGameMode::OnShot(int32 Damage)
{
	ASbdPlayerPawn* Pawn = Cast<ASbdPlayerPawn>(UGameplayStatics::GetPlayerPawn(this, 0));
	if (!Pawn)
	{
		return;
	}
	FVector Point;
	if (ASbdEnemyActor* Enemy = Cast<ASbdEnemyActor>(Pawn->Trace(Point)))
	{
		sbd_cmd C{};
		C.kind = SBD_CMD_HIT;
		C.target = Enemy->GetEntity();
		C.amount = Damage;
		C.point = { (float)Point.X, (float)Point.Y, (float)Point.Z };
		Pending.Add(C);
	}
}

void ASbdGameMode::OnState(uint32 State)
{
	ASbdPlayerPawn* Pawn = Cast<ASbdPlayerPawn>(UGameplayStatics::GetPlayerPawn(this, 0));
	if (Pawn)
	{
		Pawn->SetInputEnabled(State == SBD_STATE_PLAYING);
	}

	switch (State)
	{
	case SBD_STATE_GAME_OVER:
	{
		const bool bBeaten = sbd_world_high_score(World) > HighScoreAtRunStart;
		if (bBeaten) SaveHighScore();
		Banner = bBeaten ? FString::Printf(TEXT("High Score! %d  (Enter to restart)"), sbd_world_high_score(World))
		                 : FString(TEXT("Game Over!  (Enter to restart)"));
		break;
	}
	case SBD_STATE_PAUSED:
		Banner = TEXT("Paused");
		break;
	case SBD_STATE_PLAYING:
		Banner.Reset();
		break;
	case SBD_STATE_RESTARTING:
		for (TPair<uint32, TWeakObjectPtr<ASbdEnemyActor>>& P : Views)
		{
			if (P.Value.IsValid()) P.Value->Destroy();
		}
		Views.Reset();
		EnemiesAlive = 0;
		HighScoreAtRunStart = sbd_world_high_score(World);
		if (Pawn) Pawn->ResetPose();
		break;
	}
}

void ASbdGameMode::PlayEffect(uint32 EffectId, const FVector& Pos)
{
	if (const TObjectPtr<UNiagaraSystem>* Sys = EffectSystems.Find((int32)EffectId))
	{
		if (*Sys)
		{
			UNiagaraFunctionLibrary::SpawnSystemAtLocation(GetWorld(), *Sys, Pos);
			return;
		}
	}

	// No Niagara system mapped: draw a short-lived debug marker so effects are still visible.
	switch (EffectId)
	{
	case SBD_FX_HIT: DrawDebugSphere(GetWorld(), Pos, 12.f, 8, FColor::Yellow, false, 0.25f); break;
	case SBD_FX_DEATH: DrawDebugSphere(GetWorld(), Pos, 30.f, 8, FColor::Red, false, 0.5f); break;
	case SBD_FX_MUZZLE: DrawDebugSphere(GetWorld(), Pos, 6.f, 6, FColor::White, false, 0.08f); break;
	case SBD_FX_SPAWN: DrawDebugSphere(GetWorld(), Pos, 25.f, 8, FColor::Cyan, false, 0.5f); break;
	default: break;
	}
}

#include "SbdEnemyActor.h"
#include "SbdGameMode.h"
#include "AIController.h"
#include "Components/CapsuleComponent.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "NavigationSystem.h"
#include "UObject/ConstructorHelpers.h"

ASbdEnemyActor::ASbdEnemyActor()
{
	PrimaryActorTick.bCanEverTick = true;
	AIControllerClass = AAIController::StaticClass();
	AutoPossessAI = EAutoPossessAI::PlacedInWorldOrSpawned;

	GetCapsuleComponent()->InitCapsuleSize(40.f, 60.f);
	GetCapsuleComponent()->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
	GetCharacterMovement()->MaxWalkSpeed = 300.f;

	Body = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));
	Body->SetupAttachment(RootComponent);
	Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Body->SetRelativeScale3D(FVector(0.8f, 0.8f, 1.2f));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	if (Cylinder.Succeeded())
	{
		Body->SetStaticMesh(Cylinder.Object);
	}
}

void ASbdEnemyActor::Init(uint32 InEntity, ASbdGameMode* InMode, AActor* InTarget, float InSinkSpeed)
{
	Entity = InEntity;
	Mode = InMode;
	Target = InTarget;
	SinkSpeed = InSinkSpeed * 100.f; // core units are metres; Unreal uses centimetres
}

void ASbdEnemyActor::OnDied()
{
	bDead = true;
	SetActorEnableCollision(false);
	if (AController* C = GetController())
	{
		C->StopMovement();
	}
	GetCharacterMovement()->DisableMovement();
}

void ASbdEnemyActor::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (ASbdGameMode* M = Mode.Get())
	{
		if (!M->IsPlaying())
		{
			return;
		}
	}

	if (bDead)
	{
		AddActorWorldOffset(FVector(0.f, 0.f, -SinkSpeed * DeltaSeconds));
		return;
	}
	AActor* T = Target.Get();
	if (!T)
	{
		return;
	}

	// Chase on the nav mesh when one exists, otherwise steer straight at the target.
	UNavigationSystemV1* Nav = UNavigationSystemV1::GetCurrent(GetWorld());
	AAIController* AI = Cast<AAIController>(GetController());
	if (AI && Nav && Nav->GetDefaultNavDataInstance())
	{
		AI->MoveToActor(T, AttackRange * 0.5f);
	}
	else
	{
		FVector Dir = T->GetActorLocation() - GetActorLocation();
		Dir.Z = 0.f;
		AddMovementInput(Dir.GetSafeNormal());
	}

	const bool bNow = FVector::Dist2D(T->GetActorLocation(), GetActorLocation()) <= AttackRange;
	if (bNow != bInRange)
	{
		bInRange = bNow;
		if (ASbdGameMode* M = Mode.Get())
		{
			M->SendEnemyInRange(Entity, bInRange);
		}
	}
}

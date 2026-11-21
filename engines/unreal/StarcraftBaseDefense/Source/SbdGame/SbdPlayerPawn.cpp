#include "SbdPlayerPawn.h"
#include "SbdGameMode.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "GameFramework/FloatingPawnMovement.h"
#include "GameFramework/PlayerController.h"
#include "Engine/World.h"

ASbdPlayerPawn::ASbdPlayerPawn()
{
	PrimaryActorTick.bCanEverTick = false;
	bUseControllerRotationYaw = true;
	bUseControllerRotationPitch = true;

	Capsule = CreateDefaultSubobject<UCapsuleComponent>(TEXT("Capsule"));
	Capsule->InitCapsuleSize(40.f, 85.f);
	Capsule->SetCollisionProfileName(TEXT("Pawn"));
	RootComponent = Capsule;

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(Capsule);
	Camera->SetRelativeLocation(FVector(0.f, 0.f, 70.f));
	Camera->bUsePawnControlRotation = true;

	Movement = CreateDefaultSubobject<UFloatingPawnMovement>(TEXT("Movement"));
	Movement->MaxSpeed = 600.f; // 6 m/s, like PlayerMovement.speed in v1.00.01
}

void ASbdPlayerPawn::SetupPlayerInputComponent(UInputComponent* Input)
{
	Super::SetupPlayerInputComponent(Input);
	Input->BindAxis("MoveForward", this, &ASbdPlayerPawn::MoveForward);
	Input->BindAxis("MoveRight", this, &ASbdPlayerPawn::MoveRight);
	Input->BindAxis("LookUp", this, &ASbdPlayerPawn::LookUp);
	Input->BindAxis("Turn", this, &ASbdPlayerPawn::Turn);
	Input->BindAction("Fire", IE_Pressed, this, &ASbdPlayerPawn::FirePressed);
	Input->BindAction("Fire", IE_Released, this, &ASbdPlayerPawn::FireReleased);
	Input->BindAction("Pause", IE_Pressed, this, &ASbdPlayerPawn::PausePressed).bExecuteWhenPaused = true;
	Input->BindAction("Restart", IE_Pressed, this, &ASbdPlayerPawn::RestartPressed);
}

void ASbdPlayerPawn::MoveForward(float Value)
{
	if (bInputEnabled && Value != 0.f) AddMovementInput(GetActorForwardVector(), Value);
}

void ASbdPlayerPawn::MoveRight(float Value)
{
	if (bInputEnabled && Value != 0.f) AddMovementInput(GetActorRightVector(), Value);
}

void ASbdPlayerPawn::LookUp(float Value)
{
	if (bInputEnabled) AddControllerPitchInput(Value);
}

void ASbdPlayerPawn::Turn(float Value)
{
	if (bInputEnabled) AddControllerYawInput(Value);
}

void ASbdPlayerPawn::PausePressed()
{
	if (ASbdGameMode* M = GetWorld()->GetAuthGameMode<ASbdGameMode>()) M->SendSimple(SBD_CMD_PAUSE_TOGGLE);
}

void ASbdPlayerPawn::RestartPressed()
{
	if (ASbdGameMode* M = GetWorld()->GetAuthGameMode<ASbdGameMode>()) M->SendRestartIfGameOver();
}

FVector ASbdPlayerPawn::GetMuzzleLocation() const
{
	return Camera->GetComponentLocation();
}

AActor* ASbdPlayerPawn::Trace(FVector& OutPoint) const
{
	const FVector From = Camera->GetComponentLocation();
	const FVector To = From + Camera->GetForwardVector() * RayRange;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(SbdTrace), false, this);
	FHitResult Hit;
	if (GetWorld()->LineTraceSingleByChannel(Hit, From, To, ECC_Visibility, Params))
	{
		OutPoint = Hit.ImpactPoint;
		return Hit.GetActor();
	}
	OutPoint = To;
	return nullptr;
}

void ASbdPlayerPawn::ResetPose()
{
	SetActorLocationAndRotation(FVector(0.f, 0.f, 100.f), FRotator::ZeroRotator);
	if (AController* C = GetController())
	{
		C->SetControlRotation(FRotator::ZeroRotator);
	}
}

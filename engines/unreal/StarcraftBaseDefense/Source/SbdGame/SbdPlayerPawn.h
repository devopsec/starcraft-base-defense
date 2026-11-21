#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "SbdPlayerPawn.generated.h"

class UCameraComponent;
class UCapsuleComponent;
class UFloatingPawnMovement;

/** First-person pawn: movement, aiming and the line trace. Fire-rate and damage rules live in the core. */
UCLASS()
class SBDGAME_API ASbdPlayerPawn : public APawn
{
	GENERATED_BODY()

public:
	ASbdPlayerPawn();

	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	bool WantsToFire() const { return bFireHeld && bInputEnabled; }
	void SetInputEnabled(bool bEnabled) { bInputEnabled = bEnabled; }
	FVector GetMuzzleLocation() const;

	/** Line trace along the view direction. Returns the hit actor (may be null) and the hit point. */
	AActor* Trace(FVector& OutPoint) const;
	void ResetPose();

	UPROPERTY(EditAnywhere, Category = "Sbd")
	float RayRange = 10000.f;

private:
	void MoveForward(float Value);
	void MoveRight(float Value);
	void LookUp(float Value);
	void Turn(float Value);
	void FirePressed() { bFireHeld = true; }
	void FireReleased() { bFireHeld = false; }
	void PausePressed();
	void RestartPressed();

	UPROPERTY(VisibleAnywhere)
	TObjectPtr<UCapsuleComponent> Capsule;
	UPROPERTY(VisibleAnywhere)
	TObjectPtr<UCameraComponent> Camera;
	UPROPERTY(VisibleAnywhere)
	TObjectPtr<UFloatingPawnMovement> Movement;

	bool bFireHeld = false;
	bool bInputEnabled = true;
};

#include "SbdHud.h"
#include "SbdGameMode.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

void ASbdHud::DrawHUD()
{
	Super::DrawHUD();
	const ASbdGameMode* Mode = GetWorld()->GetAuthGameMode<ASbdGameMode>();
	if (!Mode || !Canvas)
	{
		return;
	}

	UFont* Font = GEngine->GetMediumFont();
	DrawText(FString::Printf(TEXT("Score: %d    High Score: %d"), Mode->GetScore(), Mode->GetHighScore()), FLinearColor::White, 16.f, 12.f, Font, 1.4f);
	DrawText(FString::Printf(TEXT("Health: %d    Enemies: %d"), Mode->GetPlayerHealth(), Mode->GetEnemiesAlive()), FLinearColor::White, 16.f, 40.f, Font, 1.4f);

	const FString Banner = Mode->GetBannerText();
	if (!Banner.IsEmpty())
	{
		float W = 0.f, H = 0.f;
		GetTextSize(Banner, W, H, Font, 2.f);
		DrawText(Banner, FLinearColor::Yellow, (Canvas->SizeX - W) * 0.5f, (Canvas->SizeY - H) * 0.5f, Font, 2.f);
	}
	if (Mode->GetHurtFlash() > 0.f)
	{
		DrawRect(FLinearColor(1.f, 0.f, 0.f, 0.35f * Mode->GetHurtFlash()), 0.f, 0.f, Canvas->SizeX, Canvas->SizeY);
	}
}

using Godot;
using Sbd.Native;

namespace StarcraftBaseDefense;

/// <summary>Maps core effect IDs (SBD_FX_*) to Godot particles, lights and a screen flash.</summary>
public partial class EffectPlayer : Node3D
{
    private ColorRect flash;

    public void AttachFlash(ColorRect rect)
    {
        flash = rect;
    }

    public override void _Process(double delta)
    {
        if (flash != null && flash.Color.A > 0)
        {
            Color c = flash.Color;
            c.A = Mathf.Max(0, c.A - 3f * (float)delta);
            flash.Color = c;
        }
    }

    public void Play(uint effectId, Vector3 position)
    {
        switch (effectId)
        {
            case SbdFx.Hit: Burst(position, new Color(1f, 0.9f, 0.4f), 12, 0.25f); break;
            case SbdFx.Death: Burst(position, new Color(0.9f, 0.2f, 0.1f), 30, 0.6f); break;
            case SbdFx.Muzzle: Burst(position, new Color(1f, 0.95f, 0.7f), 6, 0.1f); break;
            case SbdFx.Spawn: Burst(position, new Color(0.4f, 0.6f, 1f), 16, 0.5f); break;
            case SbdFx.PlayerHurt:
                if (flash != null) flash.Color = new Color(1, 0, 0, 0.35f);
                break;
            // SbdFx.DeathSink: handled by the enemy view's sinking motion.
        }
    }

    private void Burst(Vector3 position, Color color, int amount, float lifetime)
    {
        var p = new CpuParticles3D
        {
            Emitting = true,
            OneShot = true,
            Amount = amount,
            Lifetime = lifetime,
            Explosiveness = 1f,
            Direction = Vector3.Up,
            Spread = 180f,
            InitialVelocityMin = 1f,
            InitialVelocityMax = 3f,
            Mesh = new SphereMesh { Radius = 0.04f, Height = 0.08f },
            MaterialOverride = new StandardMaterial3D { AlbedoColor = color, ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded },
            Position = position,
        };
        AddChild(p);
        GetTree().CreateTimer(lifetime + 0.2).Timeout += p.QueueFree;
    }
}

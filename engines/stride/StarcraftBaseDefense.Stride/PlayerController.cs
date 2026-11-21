using Stride.Core.Mathematics;
using Stride.Engine;
using Stride.Input;
using Stride.Physics;

namespace StarcraftBaseDefense.Adapter;

/// <summary>First-person movement and aiming. Shooting rules live in the core; this does the raycast.</summary>
public class PlayerController : SyncScript
{
    public GameHost Host;
    public bool InputEnabled = true;
    public float Speed = 6.0f;
    public float RayRange = 100.0f;

    private float yaw;
    private float pitch;

    public bool WantsToFire { get { return InputEnabled && Input.IsMouseButtonDown(MouseButton.Left); } }
    public Vector3 MuzzlePosition { get { return Entity.Transform.WorldMatrix.TranslationVector; } }

    public override void Start()
    {
        Input.LockMousePosition(true);
        Game.IsMouseVisible = false;
    }

    public override void Update()
    {
        if (!InputEnabled) return;
        float dt = (float)Game.UpdateTime.Elapsed.TotalSeconds;

        yaw -= Input.MouseDelta.X * 2.0f;
        pitch = MathUtil.Clamp(pitch - Input.MouseDelta.Y * 2.0f, -1.4f, 1.4f);
        Entity.Transform.Rotation = Quaternion.RotationYawPitchRoll(yaw, pitch, 0);

        Vector3 move = Vector3.Zero;
        if (Input.IsKeyDown(Keys.W)) move.Z -= 1;
        if (Input.IsKeyDown(Keys.S)) move.Z += 1;
        if (Input.IsKeyDown(Keys.A)) move.X -= 1;
        if (Input.IsKeyDown(Keys.D)) move.X += 1;
        if (move != Vector3.Zero)
        {
            move.Normalize();
            Vector3 world = Vector3.Transform(move, Quaternion.RotationY(yaw));
            Entity.Transform.Position += world * Speed * dt;
        }
    }

    public bool Raycast(Simulation simulation, out Vector3 point, out EnemyView enemy)
    {
        Entity.Transform.UpdateWorldMatrix();
        Vector3 from = MuzzlePosition;
        Vector3 forward = Vector3.Transform(-Vector3.UnitZ, Entity.Transform.Rotation);
        point = from + forward * RayRange;
        enemy = null;
        if (simulation != null && simulation.Raycast(from, from + forward * RayRange, out HitResult hit) && hit.Succeeded)
        {
            point = hit.Point;
            enemy = hit.Collider.Entity.Get<EnemyView>();
        }
        return enemy != null;
    }

    public void ResetPose()
    {
        yaw = 0;
        pitch = 0;
        Entity.Transform.Position = new Vector3(0, 1.6f, 0);
        Entity.Transform.Rotation = Quaternion.Identity;
    }
}

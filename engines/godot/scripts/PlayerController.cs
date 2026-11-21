using Godot;

namespace StarcraftBaseDefense;

/// <summary>First-person player: movement and aiming. Shooting rules live in the core; this does the raycast.</summary>
public partial class PlayerController : CharacterBody3D
{
    [Export] public float Speed = 6.0f;
    [Export] public float RayRange = 100.0f;

    public Camera3D Camera { get; private set; }
    public bool InputEnabled { get; set; } = true;

    private RayCast3D ray;
    private float pitch;

    public override void _Ready()
    {
        CollisionLayer = 4;
        CollisionMask = 1;
        AddChild(new CollisionShape3D
        {
            Shape = new CapsuleShape3D { Radius = 0.4f, Height = 1.7f },
            Position = new Vector3(0, 0.85f, 0),
        });
        Camera = new Camera3D { Position = new Vector3(0, 1.6f, 0), Current = true };
        AddChild(Camera);
        ray = new RayCast3D
        {
            TargetPosition = new Vector3(0, 0, -RayRange),
            CollisionMask = 1 | 2,
            CollideWithAreas = false,
        };
        Camera.AddChild(ray);
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (!InputEnabled) return;
        if (@event is InputEventMouseMotion motion && Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            RotateY(-motion.Relative.X * 0.002f);
            pitch = Mathf.Clamp(pitch - motion.Relative.Y * 0.002f, -1.4f, 1.4f);
            Camera.Rotation = new Vector3(pitch, 0, 0);
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        if (!InputEnabled)
        {
            Velocity = Vector3.Zero;
            return;
        }
        Vector2 input = Input.GetVector("sbd_left", "sbd_right", "sbd_forward", "sbd_back");
        Vector3 move = GlobalTransform.Basis * new Vector3(input.X, 0, input.Y);
        Velocity = move * Speed;
        MoveAndSlide();
    }

    public bool WantsToFire()
    {
        return InputEnabled && Input.IsActionPressed("sbd_fire");
    }

    public Vector3 MuzzlePosition { get { return Camera.GlobalPosition; } }

    /// <summary>Raycasts along the view direction. Returns the hit collider (may be null) and the hit point.</summary>
    public GodotObject Raycast(out Vector3 point)
    {
        ray.ForceRaycastUpdate();
        if (ray.IsColliding())
        {
            point = ray.GetCollisionPoint();
            return ray.GetCollider();
        }
        point = Camera.GlobalPosition + -Camera.GlobalTransform.Basis.Z * RayRange;
        return null;
    }

    public void ResetPose()
    {
        GlobalPosition = Vector3.Zero;
        Rotation = Vector3.Zero;
        pitch = 0;
        Camera.Rotation = Vector3.Zero;
    }
}

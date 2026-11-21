using System;
using Godot;

namespace StarcraftBaseDefense;

/// <summary>View of one core enemy: chases the player on the navigation mesh; the core owns health and damage.</summary>
public partial class EnemyView : CharacterBody3D
{
    [Export] public float Speed = 3.0f;
    [Export] public float AttackRange = 1.5f;

    public uint Entity { get; private set; }

    private NavigationAgent3D agent;
    private Node3D target;
    private Action<uint, bool> inRangeChanged;
    private bool inRange;
    private bool dead;
    private bool sinking;
    private float sinkSpeed;

    public override void _Ready()
    {
        agent = GetNode<NavigationAgent3D>("NavigationAgent3D");
        const string modelPath = "res://assets/models/Zombunny.fbx";
        if (ResourceLoader.Exists(modelPath) && GD.Load<PackedScene>(modelPath) is PackedScene model)
        {
            AddChild(model.Instantiate<Node3D>());
            return;
        }

        // Fallback when the model is not imported: a plain capsule.
        AddChild(new MeshInstance3D
        {
            Mesh = new CapsuleMesh { Radius = 0.4f, Height = 1.2f },
            Position = new Vector3(0, 0.6f, 0),
            MaterialOverride = new StandardMaterial3D { AlbedoColor = new Color(0.8f, 0.45f, 0.2f) },
        });
    }

    public void Init(uint entity, Node3D player, float sinkSpeedPerSecond, Action<uint, bool> onInRangeChanged)
    {
        Entity = entity;
        target = player;
        sinkSpeed = sinkSpeedPerSecond;
        inRangeChanged = onInRangeChanged;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (sinking)
        {
            GlobalPosition += Vector3.Down * sinkSpeed * (float)delta;
            return;
        }
        if (dead || target == null) return;

        agent.TargetPosition = target.GlobalPosition;
        Vector3 direction = agent.GetNextPathPosition() - GlobalPosition;
        direction.Y = 0;
        Velocity = direction.LengthSquared() > 0.0001f ? direction.Normalized() * Speed : Vector3.Zero;
        MoveAndSlide();

        bool now = GlobalPosition.DistanceTo(target.GlobalPosition) <= AttackRange;
        if (now != inRange)
        {
            inRange = now;
            inRangeChanged?.Invoke(Entity, now);
        }
    }

    /// <summary>Core event ENEMY_DIED: stop shots from hitting and start sinking (core despawns it later).</summary>
    public void OnDied()
    {
        dead = true;
        CollisionLayer = 0;
        sinking = true;
    }
}

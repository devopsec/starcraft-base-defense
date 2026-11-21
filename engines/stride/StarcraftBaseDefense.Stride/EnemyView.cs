using System;
using Stride.Core.Mathematics;
using Stride.Engine;

namespace StarcraftBaseDefense.Adapter;

/// <summary>View of one core enemy: chases the player; the core owns health and damage.</summary>
public class EnemyView : SyncScript
{
    public Entity Target;
    public uint EntityId;
    public float SinkSpeed = 2.5f;
    public float Speed = 3.0f;
    public float AttackRange = 1.5f;
    public Action<uint, bool> OnInRangeChanged;

    private bool inRange;
    private bool dead;

    public void OnDied()
    {
        dead = true;
        // Kinematic body is removed so later shots pass through the sinking corpse.
        var body = Entity.Get<Stride.Physics.RigidbodyComponent>();
        if (body != null) Entity.Remove(body);
    }

    public override void Update()
    {
        float dt = (float)Game.UpdateTime.Elapsed.TotalSeconds;
        if (dead)
        {
            Entity.Transform.Position += Vector3.UnitY * -SinkSpeed * dt;
            return;
        }
        if (Target == null) return;

        // Open arena: steer straight at the player. Navigation meshes need Game Studio assets (follow-up).
        Vector3 to = Target.Transform.Position - Entity.Transform.Position;
        to.Y = 0;
        float distance = to.Length();
        if (distance > 0.01f)
        {
            Entity.Transform.Position += to / distance * Speed * dt;
            Entity.Transform.UpdateWorldMatrix();
            var body = Entity.Get<Stride.Physics.RigidbodyComponent>();
            body?.UpdatePhysicsTransformation();
        }

        bool now = distance <= AttackRange;
        if (now != inRange)
        {
            inRange = now;
            OnInRangeChanged?.Invoke(EntityId, now);
        }
    }
}

using System.Collections.Generic;

/// <summary>Maps core entity handles to the Unity enemy views that render them.</summary>
public class EntityViewRegistry
{
    private readonly Dictionary<uint, EnemyHealth> views = new Dictionary<uint, EnemyHealth>();

    public int Count { get { return views.Count; } }

    public void Add(uint entity, EnemyHealth view)
    {
        views[entity] = view;
    }

    public bool TryGet(uint entity, out EnemyHealth view)
    {
        // A view destroyed by the engine (scene change) compares equal to null.
        return views.TryGetValue(entity, out view) && view != null;
    }

    public void Remove(uint entity)
    {
        views.Remove(entity);
    }

    public void Clear()
    {
        views.Clear();
    }
}

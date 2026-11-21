using UnityEngine;

/// <summary>Creates enemy views when the core spawns an enemy. The spawn timer and cap live in the core.</summary>
public class EnemyManager : MonoBehaviour
{
    public GameObject enemy;                // The enemy prefab to be spawned.
    public Transform[] spawnPoints;         // An array of the spawn points this enemy can spawn from.

    void Awake ()
    {
        GameHost.Instance.Spawner = this;
    }

    /// <param name="entity">Core entity handle.</param>
    /// <param name="roll">Random value from the core (deterministic per seed); picks the spawn point.</param>
    public EnemyHealth SpawnView (uint entity, int roll)
    {
        if (spawnPoints == null || spawnPoints.Length == 0 || enemy == null)
        {
            return null;
        }

        Transform point = spawnPoints[roll % spawnPoints.Length];
        GameObject go = Instantiate (enemy, point.position, point.rotation);
        EnemyHealth view = go.GetComponent<EnemyHealth> ();
        if (view != null)
        {
            view.Bind (entity);
        }
        return view;
    }
}

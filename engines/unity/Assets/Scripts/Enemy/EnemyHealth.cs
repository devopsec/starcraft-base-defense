using UnityEngine;

/// <summary>
/// View of one core enemy. The Zig core owns health, damage, score and despawn; this component
/// only plays animation, audio, particles and the sinking motion.
/// </summary>
public class EnemyHealth : MonoBehaviour
{
    public AudioClip deathClip;                 // The sound to play when the enemy dies.
    public int currentHealth;                   // Read-only mirror of the core's value (used by EnemyMovement).

    public uint Entity { get; private set; }    // Core entity handle, assigned by EnemyManager.SpawnView.

    Animator anim;
    AudioSource enemyAudio;
    ParticleSystem hitParticles;
    CapsuleCollider capsuleCollider;
    bool isSinking;

    void Awake ()
    {
        anim = GetComponent <Animator> ();
        enemyAudio = GetComponent <AudioSource> ();
        hitParticles = GetComponentInChildren <ParticleSystem> ();
        capsuleCollider = GetComponent <CapsuleCollider> ();

        GameHost host = GameHost.Instance;
        currentHealth = host != null ? (int)host.Config.EnemyStartHealth : 100;
    }

    public void Bind (uint entity)
    {
        Entity = entity;
    }

    void Update ()
    {
        if (isSinking)
        {
            transform.Translate (-Vector3.up * GameHost.Instance.Config.SinkSpeed * Time.deltaTime);
        }
    }

    // Core event: ENEMY_HURT
    public void OnHurt (int amount, Vector3 hitPoint)
    {
        currentHealth -= amount;
        enemyAudio.Play ();
        hitParticles.transform.position = hitPoint;
        hitParticles.Play ();
    }

    // Core event: ENEMY_DIED (score was already awarded by the core)
    public void OnDied ()
    {
        currentHealth = 0;
        capsuleCollider.isTrigger = true;
        anim.SetTrigger ("Dead");
        enemyAudio.clip = deathClip;
        enemyAudio.Play ();
    }

    // Called by an animation event of the death clip. Despawn is decided by the core (ENEMY_DESPAWN).
    public void StartSinking ()
    {
        if (isSinking) return;

        GetComponent <UnityEngine.AI.NavMeshAgent> ().enabled = false;
        GetComponent <Rigidbody> ().isKinematic = true;
        isSinking = true;
    }
}

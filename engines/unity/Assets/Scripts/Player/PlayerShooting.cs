using UnityEngine;
using UnitySampleAssets.CrossPlatformInput;
using Sbd.Native;

/// <summary>
/// Engine side of shooting: reads input, performs the raycast and plays effects. The core decides
/// whether a shot is allowed (fire rate) and how much damage it deals (SHOT event, then HIT command).
/// </summary>
public class PlayerShooting : MonoBehaviour
{
    public float range = 100f;                      // The distance the gun can fire.
    public VRTK.VRTK_ControllerEvents controllerEvents; 

    public PlayerHealth player_health; 

    float timer;                                    // Time since the last shot (effects only).
    Ray shootRay = new Ray();                       // A ray from the gun end forwards.
    RaycastHit shootHit;                            // A raycast hit to get information about what was hit.
    ParticleSystem gunParticles;                    // Reference to the particle system.
    LineRenderer gunLine;                           // Reference to the line renderer.
    AudioSource gunAudio;                           // Reference to the audio source.
    Light gunLight;                                 // Reference to the light component.
	public Light faceLight;								// Duh
    float effectsDisplayTime = 0.2f;                // The proportion of the fire interval that the effects will display for.


    // Set up upd broadcast object 
    public UDP_Send dataBroadcast;


    void Awake ()
    {
        gunParticles = GetComponent<ParticleSystem> ();
        gunLine = GetComponent <LineRenderer> ();
        gunAudio = GetComponent<AudioSource> ();
        gunLight = GetComponent<Light> ();

        GameHost.Instance.Shooter = this;
    }


    void Update ()
    {
        timer += Time.deltaTime;
        float fireRate = GameHost.Instance.Config.FireRate;

#if !MOBILE_INPUT
        if(!player_health.isDead && controllerEvents.triggerPressed && Time.timeScale != 0 )
        {
            RequestShot ();
        }
#else
        if (CrossPlatformInputManager.GetAxisRaw("Mouse X") != 0 || CrossPlatformInputManager.GetAxisRaw("Mouse Y") != 0)
        {
            RequestShot ();
        }
#endif
        if(timer >= fireRate * effectsDisplayTime)
        {
            DisableEffects ();
        }


        if(timer >= fireRate)
        {
            DisableHapticBullet(); 
        }
    }

    void OnDisable()
    {
        DisableHapticBullet();
    }

    public void DisableHapticBullet()
    {
        dataBroadcast.Send_Stop();
    }

    public void DisableEffects ()
    {
        gunLine.enabled = false;
		faceLight.enabled = false;
        gunLight.enabled = false;
    }

    void RequestShot ()
    {
        GameHost.Instance.Send (SbdCmd.Make (SbdCmdKind.Fire, 0, 0, ToCore (transform.position)));
    }

    static SbdVec3 ToCore (Vector3 v)
    {
        return new SbdVec3 (v.x, v.y, v.z);
    }

    // Core event: SHOT (value = damage per shot). The fire-rate gate already passed.
    public void OnShot (int damage)
    {
        dataBroadcast.Send_Command();

        timer = 0f;

        gunAudio.Play ();

        gunLight.enabled = true;
		faceLight.enabled = true;

        gunParticles.Stop ();
        gunParticles.Play ();

        gunLine.enabled = true;
        gunLine.SetPosition(0, transform.position);

        shootRay.origin = transform.position;
        shootRay.direction = transform.forward;

        if (Physics.Raycast (shootRay, out shootHit, range))
        {
            EnemyHealth enemyHealth = shootHit.collider.GetComponent <EnemyHealth> ();

            if(enemyHealth != null && enemyHealth.Entity != 0)
            {
                GameHost.Instance.Send (SbdCmd.Make (SbdCmdKind.Hit, enemyHealth.Entity, damage, ToCore (shootHit.point)));
            }

            gunLine.SetPosition (1, shootHit.point);
        }
        else
        {
            gunLine.SetPosition (1, shootRay.origin + shootRay.direction * range);
        }
    }
}

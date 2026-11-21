using UnityEngine;
using Sbd.Native;

/// <summary>Reports whether the player is in attack range; the core owns cooldown and damage.</summary>
public class EnemyAttack : MonoBehaviour
{
    Animator anim;
    GameObject player;
    EnemyHealth enemyHealth;
    bool playerDeadSignaled;

    void Awake ()
    {
        player = GameObject.FindGameObjectWithTag ("Player");
        enemyHealth = GetComponent<EnemyHealth>();
        anim = GetComponent <Animator> ();
    }

    void OnTriggerEnter (Collider other)
    {
        if(other.gameObject == player)
        {
            SetInRange (1);
        }
    }

    void OnTriggerExit (Collider other)
    {
        if(other.gameObject == player)
        {
            SetInRange (0);
        }
    }

    void SetInRange (int inRange)
    {
        GameHost host = GameHost.Instance;
        if (host != null && enemyHealth.Entity != 0)
        {
            host.Send (SbdCmd.Make (SbdCmdKind.EnemyInRange, enemyHealth.Entity, inRange));
        }
    }

    void Update ()
    {
        GameHost host = GameHost.Instance;
        if(!playerDeadSignaled && host != null && host.IsGameOver)
        {
            playerDeadSignaled = true;
            anim.SetTrigger ("PlayerDead");
        }
    }
}

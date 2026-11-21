using UnityEngine;
using UnityEngine.UI;
using UnityEngine.SceneManagement;

/// <summary>View of the player's health. Damage, death and high score are decided by the core.</summary>
public class PlayerHealth : MonoBehaviour
{
    public int currentHealth;                                   // Read-only mirror of the core's value.
    public Slider healthSlider;                                 // Reference to the UI's health bar.
    public Image damageImage;                                   // Reference to an image to flash on the screen on being hurt.
    public AudioClip deathClip;                                 // The audio clip to play when the player dies.
    public float flashSpeed = 3f;                               // The speed the damageImage will fade at.
    public Color flashColour = new Color(1f, 0f, 0f, 0.1f);     // The colour the damageImage is set to, to flash.

    AudioSource playerAudio;
    public bool isDead;                                         // Mirror of the core's player-died state.
    bool damaged;

    void Awake ()
    {
        playerAudio = GetComponentInChildren<AudioSource> ();

        GameHost host = GameHost.Instance;
        host.Player = this;
        currentHealth = host.PlayerHealthValue;
    }

    void Update ()
    {
        if(damaged)
        {
            damageImage.color = flashColour;
        }
        else
        {
            damageImage.color = Color.Lerp (damageImage.color, Color.clear, flashSpeed * Time.deltaTime);
        }

        damaged = false;
    }

    // Core event: PLAYER_HURT (value = remaining health)
    public void OnHurt (int remainingHealth)
    {
        damaged = true;
        currentHealth = remainingHealth;
        healthSlider.value = currentHealth;
        playerAudio.Play ();
    }

    // Core event: PLAYER_DIED
    public void OnDied ()
    {
        isDead = true;
        playerAudio.clip = deathClip;
        playerAudio.Play ();
    }

    public void RestartLevel ()
    {
        SceneManager.LoadScene (0);
    }
}

using UnityEngine;
using UnityEngine.UI;

public class GameOverManager : MonoBehaviour
{
    public PlayerHealth playerHealth; // Reference to the player's health.
    Animator anim; // Reference to the animator component.
    //Text text;                      // Reference to the Text component.

    void Awake()
    {
        // Set up the reference.
        anim = GetComponent<Animator>();

        // Set up the reference.
        //text = GetComponent<Text>();
        //text.enabled = false; 
    }


    void Update()
    {
        // If the player has run out of health...
        if (playerHealth.currentHealth <= 0) {
            if (GetComponentInChildren<GameOverDisplayText>() != null) {
                GetComponentInChildren<GameOverDisplayText>().isDead = true;
            }

            // ... tell the animator the game is over.
            // anim.SetTrigger("GameOver");
        }
    }
}
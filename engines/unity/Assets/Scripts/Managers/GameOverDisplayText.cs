using UnityEngine;
using UnityEngine.UI;
using System.Collections;
using System;
using UnityEngine.SceneManagement;

public class GameOverDisplayText : MonoBehaviour
{
    [SerializeField] public bool isDead = false;

    Text text; // Reference to the Text component.
    float timer;
    public float time_until_reset;

    public VRTK.VRTK_ControllerEvents controllerEvents;

    void Awake()
    {
        // Set up the reference.
        text = GetComponent<Text>();
        text.enabled = false;
    }


    void Update()
    {
        // Set the displayed text to be the word "Score" followed by the score value.
        if (isDead) {
            timer += Time.deltaTime;


            if (timer >= time_until_reset) {
                text.text = "Restart?\n\n Press 'A' to accept";

                text.enabled = true;

                if (Input.GetButton("Fire1") || controllerEvents.buttonOnePressed) {
                    SceneManager.LoadScene(0);
                }
            }
            else if (HighScoreManager.high_score_flag) {
                text.text = "High Score!: \r\n  " + HighScoreManager.high_score;

                text.enabled = true;
                //HighScoreManager.high_score_flag = false; 
            }
            else {
                text.text = "Game Over!";
                text.enabled = true;
            }
        }
    }
}
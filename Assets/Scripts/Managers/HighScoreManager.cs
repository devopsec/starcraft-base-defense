using UnityEngine;
using UnityEngine.UI;
using System.Collections;

public class HighScoreManager : MonoBehaviour
{
    Text text; // Reference to the Text component.

    public static int high_score; // The player's score.
    public static bool high_score_flag;


    void Awake()
    {
        // Set up the reference.
        text = GetComponent<Text>();

        // Reset the score.
        //high_score = 0;
        high_score_flag = false;
    }


    void Update()
    {
        // Set the displayed text to be the word "Score" followed by the score value.
        text.text = "High Score: " + high_score;
    }
}
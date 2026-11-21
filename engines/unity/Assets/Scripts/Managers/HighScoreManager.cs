using UnityEngine;
using UnityEngine.UI;

public class HighScoreManager : MonoBehaviour
{
    Text text; // Reference to the Text component.

    void Awake()
    {
        text = GetComponent<Text>();
    }

    void Update()
    {
        text.text = "High Score: " + GameHost.Instance.HighScore;
    }
}

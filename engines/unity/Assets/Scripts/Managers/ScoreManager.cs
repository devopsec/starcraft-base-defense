using UnityEngine;
using UnityEngine.UI;

public class ScoreManager : MonoBehaviour
{
    Text text; // Reference to the Text component.

    void Awake()
    {
        text = GetComponent<Text>();
    }

    void Update()
    {
        text.text = "Score: " + GameHost.Instance.Score;
    }
}

using UnityEngine;

/// <summary>
/// Kept so existing scene references stay valid. Loading happens in GameHost.Awake and the
/// file format is owned by the core (see UnitySaveStore / LegacySaveImporter).
/// </summary>
public class SaveManager : MonoBehaviour
{
    private void OnDestroy()
    {
        saveGame();
    }

    public void saveGame()
    {
        if (GameHost.Instance != null)
        {
            GameHost.Instance.SaveNow();
        }
    }

    public void loadGame()
    {
        // Intentionally empty: the high score is loaded once when the host starts.
    }
}

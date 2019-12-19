using UnityEngine;
using UnityEngine.UI;
using VRTK;

public class SDKSetupSwitcherManager : VRTK_SDKSetupSwitcher
{
    protected override void Awake()
    {
#if UNITY_EDITOR
        gameObject.GetComponent<Canvas>().enabled = true;
        gameObject.GetComponent<CanvasScaler>().enabled = true;
        gameObject.GetComponent<GraphicRaycaster>().enabled = true;
#else
        gameObject.GetComponent<Canvas>().enabled = true;
        gameObject.GetComponent<CanvasScaler>().enabled = true;
        gameObject.GetComponent<GraphicRaycaster>().enabled = true;
#endif
        base.Awake();
    }
}
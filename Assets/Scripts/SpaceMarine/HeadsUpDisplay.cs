using System;
using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using Utility;
using VRTK;

public class HeadsUpDisplay : MonoBehaviour
{
    public Text enemyTracker;
    // public RectTransform enemyTrackerTrans;
    // public RectTransform healthBarTrans;
    private Transform headset;

    void Awake()
    {
        VRTK_SDKManager.AttemptAddBehaviourToToggleOnLoadedSetupChange(this);
    }
    void OnDestroy()
    {
        VRTK_SDKManager.AttemptRemoveBehaviourToToggleOnLoadedSetupChange(this);
    }

    void OnEnable()
    {
        try {
            headset = VRTK_DeviceFinder.HeadsetCamera();
        }
        catch (Exception) {
            try {
                headset = GameObject.FindGameObjectWithTag("MainCamera").transform;
                if (headset.position.y == 0) {
                    headset = null;
                    throw new Exception();
                }
            }
            catch (Exception) {
                try {
                    GameObject camRig = GameObject.FindGameObjectWithTag("CameraRig");
                    headset = General.FindChildWithTag(camRig, "MainCamera").transform;
                }
                catch (Exception) {
                    Debug.LogWarning("Camera Height auto resolution failed.. falling back on user input");
                }
            }
        }
    }

    // configure HUD settings
    IEnumerator Start() 
    {
        yield return new WaitUntil(() => CalibrateModel.calibrationComplete == true);

        GameObject headsetCamGO = headset.gameObject;
        if (!headsetCamGO.CompareTag("MainCamera")) {
            headsetCamGO = General.FindChildWithTag(headsetCamGO, "MainCamera");
        }
        Canvas headsUpDisplay = GetComponent<Canvas>();
        headsUpDisplay.worldCamera = headsetCamGO.GetComponent<Camera>();
        headsUpDisplay.renderMode = RenderMode.ScreenSpaceCamera;
    }

    void LateUpdate()
    {
        enemyTracker.text = "Enemies: " + EnemyManager.enemiesAlive;
    }
}

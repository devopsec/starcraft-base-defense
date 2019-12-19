using System;
using System.Collections;
using UnityEngine;
using Utility;
using VRTK;

public class BodyRotationHandler : MonoBehaviour
{
    // public Transform model;
    // public Transform modelHead;
    public Transform player;
    public float rotateAngle = 45.0f;
    public float rotateCheckDelay = 2.0f;
    public float rotateSeconds = 2.0f;
    private float cachedLookingDirection;
    private float prevLookingDirection;
    private float currLookingDirection;
    private float deltaAngle = 0.0f;
    private Transform headset;
    private IEnumerator rotateCoroutine;
    // private IEnumerator rotateHeadCoroutine;

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
    IEnumerator Start()
    {
        yield return new WaitUntil(() => CalibrateModel.calibrationComplete == true);
        
        cachedLookingDirection = headset.eulerAngles.y;
        prevLookingDirection = cachedLookingDirection;
        currLookingDirection = cachedLookingDirection;

        StartCoroutine(TimedUpdate());
    }

    private IEnumerator TimedUpdate()
    {
        while (true)
        {
            // check if player turned body in last rotation
            yield return new WaitForSeconds(rotateCheckDelay);
            prevLookingDirection = currLookingDirection;
            currLookingDirection = headset.eulerAngles.y;
            deltaAngle = currLookingDirection - prevLookingDirection;
            if (Mathf.Abs(deltaAngle) >= rotateAngle)  {
                // update players model to match their body's facing direction
                // since last time the models body rotated (small rotations accounted for)
                deltaAngle = currLookingDirection - cachedLookingDirection;
                cachedLookingDirection = currLookingDirection;
                if (rotateCoroutine != null)  {
                    StopCoroutine(rotateCoroutine);
                }
                // if (rotateHeadCoroutine != null)
                // {
                //     StopCoroutine(rotateCoroutine);
                // }
                // rotateCoroutine = SmoothMove.rotate(model, new Vector3(0.0f, deltaAngle, 0.0f), rotateSeconds);
                rotateCoroutine = SmoothMove.rotate(player, new Vector3(0.0f, deltaAngle, 0.0f), rotateSeconds);
                // rotateHeadCoroutine = SmoothMove.rotate(modelHead, new Vector3(0.0f, deltaAngle, 0.0f), rotateSeconds);
                StartCoroutine(rotateCoroutine);
                // StartCoroutine(rotateHeadCoroutine);
            }
        }
    }
}

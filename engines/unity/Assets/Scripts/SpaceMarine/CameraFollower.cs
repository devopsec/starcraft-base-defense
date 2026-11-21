using System;
using System.Collections;
using UnityEngine;
using VRTK;
using Utility;

public class CameraFollower : VRTK_TransformFollow
{
    public bool debugEnabled = false;
    public bool attemptAutoHeightResolution = true;
    public float initialCamHeight = 0.0f;
    public Vector3 posScaleFactors = new Vector3(1.0f,1.0f,1.0f);
    public Vector3 posAdjustments =  new Vector3(0.0f,0.0f,0.0f);
    public bool rotAboutXEnabled = true;
    public bool rotAboutYEnabled = true;
    public bool rotAboutZEnabled = true;
    private Transform headset;

    void Awake()
    {
        VRTK_SDKManager.AttemptAddBehaviourToToggleOnLoadedSetupChange(this);
    }
    void OnDestroy()
    {
        VRTK_SDKManager.AttemptRemoveBehaviourToToggleOnLoadedSetupChange(this);
    }
    
    protected override void OnEnable()
    {
        if (attemptAutoHeightResolution) {
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
        
        base.OnEnable();
    }

    IEnumerator Start() 
    {
        yield return new WaitUntil(() => CalibrateModel.calibrationComplete == true);

        if (attemptAutoHeightResolution) {
            RaycastHit hit;
            int layerMask = 1 << 9; // PreProcessing Layer
            
            /*
             * fallback on user initial height if auto resolving failed
             * otherwise calculate height from the floor
             */
            if (headset != null) {
                if (Physics.Raycast(headset.position, headset.TransformDirection(Vector3.down), out hit, Mathf.Infinity, layerMask)) {
                    if (debugEnabled) {
                        Debug.DrawRay(headset.position,headset.TransformDirection(Vector3.down) * hit.distance, Color.red, 1000.0f, false);
                    }

                    initialCamHeight = hit.distance;
                }
            }
        }

        if (debugEnabled) {
            Debug.Log("Initial camera height: " + initialCamHeight.ToString("f4"));
        }

        CacheTransforms();
    }

    protected override Vector3 GetPositionToFollow()
    {
        return new Vector3(transformToFollow.position.x, transformToFollow.position.y - initialCamHeight, transformToFollow.position.z);
    }

    protected override void SetPositionOnGameObject(Vector3 newPosition)
    {
        transformToChange.position = Vector3.Scale(newPosition, posScaleFactors) + posAdjustments;
    }

    protected override void SetRotationOnGameObject(Quaternion newRotation)
    {
        Vector3 oldAngles = transformToChange.rotation.eulerAngles;
        Vector3 newAngles = newRotation.eulerAngles;
        if (!rotAboutXEnabled) {
            newAngles.x = oldAngles.x;
        }
        if (!rotAboutYEnabled) {
            newAngles.y = oldAngles.y;
        }
        if (!rotAboutZEnabled) {
            newAngles.z = oldAngles.z;
        }

        if (debugEnabled) {
            Debug.Log("Rotation Before: " + oldAngles);
            Debug.Log("Rotation After: " + newAngles);
        }

        transformToChange.rotation = Quaternion.Euler(newAngles);
    }

}

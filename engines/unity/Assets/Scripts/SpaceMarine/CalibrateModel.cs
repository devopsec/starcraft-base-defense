using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using VRTK;
using Utility;

public class CalibrateModel : MonoBehaviour
{
    public Transform model;
    public Transform modelHead;
    public Transform modelNeckBone;
    public Transform modelLeftShoulderBone;
    public Transform modelRightShoulderBone;
    public Transform modelLeftUpperArmBone;
    public Transform modelRightUpperArmBone;
    public Transform modelLeftForeArmBone;
    public Transform modelRightForeArmBone;
    public Transform modelLeftHandBone;
    public Transform modelRightHandBone;
    public Transform modelRifle;
    [Space(10)] 
    public float magicHelmetHeight;
    public bool debug = false;

    private Transform headset;
    private Transform leftctrl;
    private Transform rightctrl;

    private float modelLeftArmLength;
    private float modelRightArmLength;
    private float playerLeftArmLength;
    private float playerRightArmLength;
    private float leftArmScale;
    private float rightArmScale;

    [HideInInspector]
    public static bool calibrationComplete = false;

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

        try {
            leftctrl = VRTK_DeviceFinder.DeviceTransform(VRTK_DeviceFinder.Devices.LeftController);
        }
        catch (Exception e) {
            Debug.Log(e);
        }

        if (leftctrl == null) {
            leftctrl = GameObject.FindGameObjectWithTag("LeftController").transform;
        }

        try {
            rightctrl = VRTK_DeviceFinder.DeviceTransform(VRTK_DeviceFinder.Devices.RightController);
        }
        catch (Exception e) {
            Debug.Log(e);
        }

        if (rightctrl == null) {
            rightctrl = GameObject.FindGameObjectWithTag("RightController").transform;
        }
    }

    IEnumerator Start() 
    {
        /* 
         * give the headsets first slot in unity script order execution
         * we need the headsets height to be tracked properly before continuing
         */
#if VRTK_DEFINE_SDK_OCULUS
        yield return new WaitForSeconds(0.1f);
#elif VRTK_DEFINE_SDK_STEAMVR
        yield return new WaitForSeconds(0.1f);
#endif

        syncModelsRotation();
        scaleModelByHeight();
        if (debug) {
            scaleModelsArmLength();
        }
        calibrationComplete = true;
    }

    // scale the models arm length to players arm length
    // player should stand in T-pose for correct results
    public void scaleModelsArmLength()
    {
        modelLeftArmLength = Vector3.Distance(modelNeckBone.position, modelLeftHandBone.position);
        modelRightArmLength = Vector3.Distance(modelNeckBone.position, modelRightHandBone.position);
        playerLeftArmLength = Vector3.Distance(headset.position, leftctrl.position);
        playerRightArmLength = Vector3.Distance(headset.position, rightctrl.position);
        leftArmScale = playerLeftArmLength / modelLeftArmLength;
        rightArmScale = playerRightArmLength / modelRightArmLength;
        modelLeftShoulderBone.localScale = new Vector3(leftArmScale, leftArmScale, leftArmScale);
        modelRightShoulderBone.localScale = new Vector3(rightArmScale, rightArmScale, rightArmScale);
        modelLeftUpperArmBone.localScale = new Vector3(leftArmScale, leftArmScale, leftArmScale);
        modelRightUpperArmBone.localScale = new Vector3(rightArmScale, rightArmScale, rightArmScale);
        modelLeftForeArmBone.localScale = new Vector3(leftArmScale, leftArmScale, leftArmScale);
        modelRightForeArmBone.localScale = new Vector3(rightArmScale, rightArmScale, rightArmScale);
    }
    
    // scale the entire model by a factor of height percentage
    // this is based on what i found to work for this specific model
    public void scaleModelByHeight()
    {
        // float size = theGameObject.GetComponent<Renderer> ().bounds.size.y;
        // Vector3 rescale = theGameObject.transform.localScale;
        // rescale.y = newSize * rescale.y / size;
        // theGameObject.transform.localScale = rescale;
        
        float scalar = headset.position.y / magicHelmetHeight;
        // model.localScale = Vector3.one;
        // model.localScale = new Vector3 (model.lossyScale.x*scalar/transform.lossyScale.x, model.lossyScale.y*scalar/transform.lossyScale.y, model.lossyScale.z*scalar/transform.lossyScale.z);
        // model.SetGlobalScale(new Vector3(model.lossyScale.x*scalar, model.lossyScale.y*scalar, model.lossyScale.z*scalar));
        model.localScale = new Vector3(model.localScale.x*scalar, model.localScale.y*scalar, model.localScale.z*scalar);
        modelRifle.localScale = new Vector3(modelRifle.localScale.x*scalar, modelRifle.localScale.y*scalar, modelRifle.localScale.z*scalar);
    }

    // synchronize rotation of model, and model head, with camera rig before startup
    private void syncModelsRotation()
    {
        float camY = headset.rotation.eulerAngles.y;
        model.rotation = Quaternion.Euler(new Vector3(model.eulerAngles.x, camY, model.eulerAngles.z));
        modelHead.rotation = Quaternion.Euler(new Vector3(modelHead.eulerAngles.x, camY, modelHead.eulerAngles.z));
    }
}
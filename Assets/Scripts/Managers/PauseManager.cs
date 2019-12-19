using UnityEngine;
using System.Collections;
using UnityEngine.UI;
using UnityEngine.Audio;
using VRTK;
using System;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class PauseManager : MonoBehaviour {
	
	public AudioMixerSnapshot paused;
	public AudioMixerSnapshot unpaused;
	
	public Canvas gameMenuCanvas;
	public Canvas highScoreCanvas;

    private VRTK_ControllerEvents controllerEvents;
    private VRTK_Pointer pointer;
    private VRTK_UIPointer uiPointer;
    private VRTK_BezierPointerRenderer bezeierPointerRenderer;
    private VRTK_StraightPointerRenderer straightPointerRenderer;
    //private Custom_VRTK_UIStraightPointerRenderer straightPointerRenderer;
    private GameObject leftctrl;
    private bool acceptingUpdates = true;

    void Awake() {
        VRTK_SDKManager.AttemptAddBehaviourToToggleOnLoadedSetupChange(this);
    }
    void OnDestroy() {
        VRTK_SDKManager.AttemptRemoveBehaviourToToggleOnLoadedSetupChange(this);
    }

    void OnEnable() {
        try {
            leftctrl = VRTK_DeviceFinder.GetControllerLeftHand();
        } catch (Exception e) {
            Debug.Log(e);
        }

        if (leftctrl == null) {
            leftctrl = GameObject.FindGameObjectWithTag("LeftController");
        }

        
        pointer = leftctrl.GetComponent<VRTK_Pointer>();
        uiPointer = leftctrl.GetComponent<VRTK_UIPointer>();
        bezeierPointerRenderer = leftctrl.GetComponent<VRTK_BezierPointerRenderer>();
        straightPointerRenderer = leftctrl.GetComponent<VRTK_StraightPointerRenderer>();
        //straightPointerRenderer = leftctrl.GetComponent<Custom_VRTK_UIStraightPointerRenderer>();
        controllerEvents = leftctrl.GetComponent<VRTK_ControllerEvents>();
    }

    void Start()
	{
		gameMenuCanvas.enabled = false;
		highScoreCanvas.enabled = true;
        if (leftctrl != null) {
            pointer.enabled = true;
            uiPointer.enabled = false;
            bezeierPointerRenderer.enabled = true;
         }
	}

    void Update()
	{
        if (!acceptingUpdates) {
            return;
        }

        if (Input.GetKeyDown(KeyCode.Escape)) {
            doUpdate();
        } 
        else if (controllerEvents.IsButtonPressed(VRTK_ControllerEvents.ButtonAlias.StartMenuPress)) {
            pointer.enabled = false;

            // game is going to be paused
            if (!gameMenuCanvas.enabled) {
                pointer.enableTeleport = false;
                pointer.pointerRenderer = straightPointerRenderer;
                pointer.activationButton = VRTK_ControllerEvents.ButtonAlias.Undefined;
                pointer.holdButtonToActivate = false;
                bezeierPointerRenderer.enabled = false;
                uiPointer.enabled = true;
                straightPointerRenderer.enabled = true;
            }
            // game is going to be unpaused
            else if (gameMenuCanvas.enabled) {
                pointer.enableTeleport = true;
                pointer.pointerRenderer = bezeierPointerRenderer;
                pointer.activationButton = VRTK_ControllerEvents.ButtonAlias.TouchpadPress;
                pointer.holdButtonToActivate = true;
                straightPointerRenderer.enabled = false;
                uiPointer.enabled = false;
                bezeierPointerRenderer.enabled = true;
            }

            pointer.enabled = true;
            
            doUpdate();
        }
	}

    void doUpdate()
    {
        acceptingUpdates = false;

        gameMenuCanvas.enabled = !gameMenuCanvas.enabled;
        highScoreCanvas.enabled = !highScoreCanvas.enabled;
        Pause();

        StartCoroutine(debounceButtonPress());
    }
	
    private IEnumerator debounceButtonPress() 
    {
        yield return new WaitUntil(() => Input.GetKeyUp(KeyCode.Escape) == true || controllerEvents.IsButtonPressed(VRTK_ControllerEvents.ButtonAlias.StartMenuPress) == false);
        acceptingUpdates = true;
    }

	public void Pause()
	{
		Time.timeScale = Time.timeScale == 0 ? 1 : 0;
		Lowpass ();
		
	}
	
	void Lowpass()
	{
		if (Time.timeScale == 0)
		{
			paused.TransitionTo(.01f);
		}
		
		else
			
		{
			unpaused.TransitionTo(.01f);
		}
	}
	
	public void Quit()
	{
		#if UNITY_EDITOR 
		EditorApplication.isPlaying = false;
		#else 
		Application.Quit();
		#endif
	}
}

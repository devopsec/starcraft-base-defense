using System;
using UnityEngine;
using System.Collections;
using UnityEditor;
using UnityEditor.SceneManagement;

[CustomEditor(typeof(InverseKinematics2))]
public class InverseKinematics2Inspector : Editor
{
    private static GUIStyle toggleButtonStyleNormal;
    private static GUIStyle toggleButtonStyleToggled;
    private static GUIContent toggleButtonGUIContentNormal;
    private static GUIContent toggleButtonGUIContentToggled;
    private bool toggleIKButtonEnabled;
    private Transform upperArm;
    private Transform forearm;
    private Transform hand;
    private Transform elbowIK;
    private Transform handIK;
    
    void OnEnable()
    {

    }

    public override void OnInspectorGUI()
    {
        /* draw the base inspector fields */
        DrawDefaultInspector();
        
        /* setup static inspector variables and data */
        if (toggleButtonStyleNormal == null) {
            toggleButtonStyleNormal = GUI.skin.button;
            toggleButtonStyleToggled = new GUIStyle(toggleButtonStyleNormal);
            toggleButtonStyleToggled.normal.background = toggleButtonStyleToggled.active.background;
            toggleButtonGUIContentNormal = new GUIContent(
                "Run IK Test",
                "Enable execution of the Inverse Kinematics script in Editor.\n" +
                "All transforms will be reset once this toggle button is disabled."
            );
            toggleButtonGUIContentToggled = new GUIContent(
                "Stop IK Test",
                "Disable execution of the Inverse Kinematics script in Editor.\n" +
                "All transforms will be reset once this toggle button is disabled."
            );
        }
        
        /* get script object */
        InverseKinematics2 script = (InverseKinematics2)target;

        /* draw custom inspector fields */
        // GUILayout.Space(20f);
        // GUILayout.Label("Editor Mode Testing", EditorStyles.boldLabel);

        GUILayout.Space(10f);
        GUILayout.BeginHorizontal();
        
        // set MonoBehaviour.runInEditMode property on script
        // not sure if Undo.RecordObject will work for this but could be simpler than serializing everything
        if ( GUILayout.Button(toggleIKButtonEnabled ? toggleButtonGUIContentToggled : toggleButtonGUIContentNormal, 
            toggleIKButtonEnabled ? toggleButtonStyleToggled : toggleButtonStyleNormal) )
        {
            toggleIKButtonEnabled = !toggleIKButtonEnabled;
            
            if (toggleIKButtonEnabled) {
                // store current values
                upperArm = script.upperArm;
                forearm = script.forearm;
                hand = script.hand;
                elbowIK = script.elbow;
                handIK = script.target;
                script.runInEditMode = true;
                Debug.Log( "toggle button enabled");
            }
            else {
                // restore previous values
                script.upperArm = upperArm;
                script.forearm = forearm;
                script.hand = hand;
                script.elbow = elbowIK;
                script.target = handIK;
                script.runInEditMode = false;
                Debug.Log("toggle button disabled");
            }
        }

        GUILayout.EndHorizontal();
        
        if (GUI.changed) {
            EditorUtility.SetDirty(script);
            EditorSceneManager.MarkSceneDirty(script.gameObject.scene);
        }
    }

    void OnSceneGUI()
    {
        // is not disabled and button state = pressed
    }

    


    


}

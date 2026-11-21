using UnityEngine;
using UnityEditor;
using System.Collections.Generic;

public class StorageClass : MonoBehaviour
{
    public static List<Transform> tfrms = new List<Transform>();
}

#if UNITY_EDITOR
public static class UtilityMenu
{
    [MenuItem("Utility/Copy Transforms")]
    public static void CopyTransforms()
    {
        if (Selection.activeGameObject != null)
        {
            foreach (Transform child in Selection.activeGameObject.transform)
            {
                StorageClass.tfrms.Add(child);
            }
        }
    }

    [MenuItem("Utility/Paste Transforms")]
    public static void PasteTransforms()
    {
        if (Selection.activeGameObject != null)
        {
            int i = 0;
            foreach (Transform child in Selection.activeGameObject.transform)
            {
                UnityEditorInternal.ComponentUtility.CopyComponent(StorageClass.tfrms[i]);
                UnityEditorInternal.ComponentUtility.PasteComponentAsNew(child.gameObject);
                i++;
            }
        }
    }
    
    [MenuItem("Utility/Print Global Position")]
    public static void PrintGlobalPosition()
    {
        if (Selection.activeGameObject != null)
        {
            Debug.Log(Selection.activeGameObject.name + " is at " + Selection.activeGameObject.transform.position.ToString("f4"));
        }
    }

    [MenuItem("Utility/Print Angle Between")]
    public static void PrintAngleBetween()
    {
        if (Selection.gameObjects != null && Selection.gameObjects.Length == 2) {
            Transform fromTransform = Selection.gameObjects[0].transform;
            Transform toTransform = Selection.gameObjects[1].transform;
            
            Quaternion fullRelativeRotation = Quaternion.Inverse(fromTransform.rotation) * toTransform.rotation;
            Quaternion rotationThisFrame = Quaternion.Slerp(Quaternion.identity, fullRelativeRotation, 1);
            //Vector3 direction = (fromTransform.rotation * rotationThisFrame) * Vector3.forward;
            Vector3 direction = fullRelativeRotation.eulerAngles;
            Debug.Log("Angle from " + Selection.gameObjects[0].name + " to " + Selection.gameObjects[1].name + ": " + fullRelativeRotation.eulerAngles.ToString("f4"));
            Debug.DrawRay(fromTransform.position, direction * 100.0f, Color.cyan, 1000.0f, false);

            // float angle = Vector3.Angle((toTransform.position - fromTransform.position).normalized, fromTransform.forward);
            // Debug.Log("Angle from " + Selection.gameObjects[0].name + " to " + Selection.gameObjects[1].name + ": " + angle.ToString("f4"));
            // Debug.DrawRay(fromTransform.position, fromTransform.TransformDirection(Vector3.forward) * 100.0f, Color.cyan, 1000.0f, false);
            // angle = Vector3.Angle(
            //     Vector3.ProjectOnPlane(fromTransform.forward, Vector3.up).normalized,
            //     Vector3.ProjectOnPlane(toTransform.position - fromTransform.position, Vector3.up).normalized
            // ); 
            // Debug.Log("Angle from " + Selection.gameObjects[0].name + " to " + Selection.gameObjects[1].name + ": " + angle.ToString("f4"));
            // Debug.DrawRay(fromTransform.position, fromTransform.TransformDirection(Vector3.forward) * 100.0f, Color.magenta, 1000.0f, false);
        }
    }
}

#endif
using UnityEngine;
using System.Collections;
using System.Collections.Generic;
 
public class EditorViewSkeleton : MonoBehaviour 
{
 
    public Transform rootNode;
    public Transform[] childNodes;
    public bool alwaysActive = false;
    public bool enabled = true;

    void OnDrawGizmos()
    {
        if (alwaysActive && enabled) {
            drawBones();
        }
    }

    void OnDrawGizmosSelected()
    {
        if (!alwaysActive && enabled) {
            drawBones();
        }
    }
 
    void drawBones()
    {
        if (rootNode == null) {
            rootNode = gameObject.transform;
        }

        if (childNodes == null || childNodes.Length == 0) {
            //get all joints to draw
            childNodes = rootNode.GetComponentsInChildren<Transform>();
        }
         
         
        foreach (Transform child in childNodes) {
            if (child == rootNode) {
                //list includes the root, if root then larger, green cube
                Gizmos.color = Color.green;
                Gizmos.DrawCube(child.position, new Vector3(.1f, .1f, .1f));
            }
            else {
                Gizmos.color = Color.blue;
                Gizmos.DrawLine(child.position, child.parent.position);
                Gizmos.DrawCube(child.position, new Vector3(.01f, .01f, .01f));
            }
        }
    }
}


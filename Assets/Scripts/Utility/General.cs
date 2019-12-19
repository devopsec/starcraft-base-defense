using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Utility
{
    public class General
    {
        public static GameObject FindChildWithTag(GameObject parent, string tag)
        {
            Transform t = parent.transform;
            for (int i = 0; i < t.childCount; i++) {
                if (t.GetChild(i).gameObject.CompareTag(tag)) {
                    return t.GetChild(i).gameObject;
                }
            }

            return null;
        }
        
        public static Vector3 AngleDifferenceClamped(Vector3 a, Vector3 b)
        {
            Vector3 diff = new Vector3();
            diff.x = b.x - a.x;
            if (diff.x > 180) diff.x -= 360;
            else if (diff.x < -180) diff.x += 360;
            diff.y = b.y - a.y;
            if (diff.y > 180) diff.y -= 360;
            else if (diff.y < -180) diff.y += 360;
            diff.z = b.z - a.z;
            if (diff.z > 180) diff.z -= 360;
            else if (diff.z < -180) diff.z += 360;
            return diff;
        }
    }
}
// derived from MoveObject.cs by Nathan St. Pierre
/* 
Usage:
    using Utility;
    void Start() {
        StartCoroutine(SmoothMove.translateTo(...));
    }
*/

namespace Utility
{
    using UnityEngine;
    using System.Collections;

    public static class SmoothMove
    {
        public static IEnumerator translateTo(Transform thisTransform, Vector3 endPos, float time)
        {
            yield return translate(thisTransform, thisTransform.position, endPos, time);
        }

        public static IEnumerator translate(Transform thisTransform, Vector3 startPos, Vector3 endPos, float time)
        {
            float rate = 1.0f / time;
            float t = 0.0f;
            while (t < 1.0) {
                t += Time.deltaTime * rate;
                thisTransform.position = Vector3.Lerp(startPos, endPos, Mathf.SmoothStep(0.0f, 1.0f, t));
                yield return null;
            }
        }

        public static IEnumerator rotateTo(Transform fromTransform, Transform toTransform, float time)
        {
            Vector3 weight = new Vector3(1, 1, 1);
            yield return rotateTo(fromTransform, toTransform, time, weight);
        }

        public static IEnumerator rotateTo(Transform fromTransform, Transform toTransform, float time, Vector3 weight)
        {
            Vector3 degrees = toTransform.rotation.eulerAngles;
            degrees.x = degrees.x * weight.x;
            degrees.y = degrees.y * weight.y;
            degrees.z = degrees.z * weight.z;
            
            float rate = 1.0f / time;
            float t = 0.0f;
            while (t < 1.0f) {
                t += Time.deltaTime * rate;
                // thisTransform.rotation = Quaternion.Slerp(startRotation, endRotation, t);
                yield return null;
            }
        }

        public static IEnumerator rotate(Transform thisTransform, Vector3 degrees, float time)
        {
            Quaternion startRotation = thisTransform.rotation;
            Quaternion endRotation = thisTransform.rotation * Quaternion.Euler(degrees);
            
            float rate = 1.0f / time;
            float t = 0.0f;
            while (t < 1.0f) {
                t += Time.deltaTime * rate;
                thisTransform.rotation = Quaternion.Slerp(startRotation, endRotation, t);
                yield return null;
            }

        }
    }
}
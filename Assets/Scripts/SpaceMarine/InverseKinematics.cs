using System.Collections;
using System.Collections.Generic;
using UnityEngine;

//[ExecuteInEditMode]
[RequireComponent(typeof(Animator))] 
public class InverseKinematics : MonoBehaviour {

    public bool ikActive = true;

    public float handLeftPosWeight = 1.0f;
    public float handLeftRotWeight = 1.0f;

    public float handRightPosWeight = 1.0f;
    public float handRightRotWeight = 1.0f;

    public Transform handLeftTransform;
    public Transform handRightTransform;

    private Animator animator;

	void Start () {
        if (animator == null) {
            animator = GetComponent<Animator>();
        }	
	}

    void LateUpdate()
    {
        // if the IK is active, set the position and rotation directly to the goal. 
        if (ikActive) {
            animator.SetIKPositionWeight(AvatarIKGoal.LeftHand, handLeftPosWeight);
            animator.SetIKRotationWeight(AvatarIKGoal.LeftHand, handLeftRotWeight);
            animator.SetIKPosition(AvatarIKGoal.LeftHand, handLeftTransform.position);
            animator.SetIKRotation(AvatarIKGoal.LeftHand, handLeftTransform.rotation);
            animator.SetIKPositionWeight(AvatarIKGoal.RightHand, handRightPosWeight);
            animator.SetIKRotationWeight(AvatarIKGoal.RightHand, handRightRotWeight);
            animator.SetIKPosition(AvatarIKGoal.RightHand, handRightTransform.position);
            animator.SetIKRotation(AvatarIKGoal.RightHand, handRightTransform.rotation);
        }
        // if the IK is not active, set the position and rotation of the hand and head back to the original position
        else {
            animator.SetIKPositionWeight(AvatarIKGoal.LeftHand, 0);
            animator.SetIKRotationWeight(AvatarIKGoal.LeftHand, 0);
            animator.SetIKPositionWeight(AvatarIKGoal.RightHand, 0);
            animator.SetIKRotationWeight(AvatarIKGoal.RightHand, 0);
        }
    }

}



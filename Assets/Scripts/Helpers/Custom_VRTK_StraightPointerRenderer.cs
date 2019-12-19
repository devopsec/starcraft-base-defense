using UnityEngine;
using VRTK;

public class Custom_VRTK_UIStraightPointerRenderer : VRTK_StraightPointerRenderer {
    protected override void CreatePointerOriginTransformFollow() {
        pointerOriginTransformFollowGameObject = new GameObject(VRTK_SharedMethods.GenerateVRTKObjectName(true, gameObject.name, "BasePointerRenderer_Origin_Smoothed"));
        pointerOriginTransformFollow = pointerOriginTransformFollowGameObject.AddComponent<VRTK_TransformFollow>();
        pointerOriginTransformFollow.enabled = false;
        pointerOriginTransformFollow.followsScale = false;

        // Set the moment to onUpdate so it is unaffected by Time.timeScale
        pointerOriginTransformFollow.moment = VRTK_TransformFollow.FollowMoment.OnUpdate;
    }
}

using UnityEngine;
using VRTK;

public class Custom_VRTK_StraightPointerRenderer : VRTK_StraightPointerRenderer {
    protected override void CreatePointerOriginTransformFollow() {
        base.CreatePointerOriginTransformFollow();

        // Set the moment to onUpdate so it is unaffected by Time.timeScale
        pointerOriginTransformFollow.moment = VRTK_TransformFollow.FollowMoment.OnUpdate;
    }
}

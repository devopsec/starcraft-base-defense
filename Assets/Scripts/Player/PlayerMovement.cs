using System;
using System.Collections;
using System.Runtime.CompilerServices;
using UnityEngine;
using UnitySampleAssets.CrossPlatformInput;

public class PlayerMovement : MonoBehaviour
{
    public float speed = 6f;            // The speed that the player will move at.
    public float fixBadMovementDelay = 2.0f;
    public Transform levelLimit1;
    public Transform levelLimit2;
    public Transform levelLimit3;
    public Transform levelLimit4;
    public Transform floor;
    public Transform ceiling;

    private Vector3 movement;                   // The vector to store the direction of the player's movement.
    private Animator anim;                      // Reference to the animator component.
    private Rigidbody playerRigidbody;          // Reference to the player's rigidbody.
    private Transform player;
    private CameraFollower[] cameraFollowers;
#if !MOBILE_INPUT
    int floorMask;                      // A layer mask so that a ray can be cast just at gameobjects on the floor layer.
    float camRayLength = 100f;          // The length of the ray from the camera into the scene.
#endif

    void Awake ()
    {
#if !MOBILE_INPUT
        // Create a layer mask for the floor layer.
        floorMask = LayerMask.GetMask ("Floor");
#endif

        // Set up references.
        anim = GetComponent <Animator> ();
        playerRigidbody = GetComponent <Rigidbody> ();
        player = gameObject.transform;
        cameraFollowers = gameObject.GetComponents<CameraFollower>();
    }

    void Start()
    {
        InvokeRepeating("FixBadMovement", fixBadMovementDelay, fixBadMovementDelay);
    }
    
    void FixedUpdate ()
    {
        // fix any bad movements by player, such as clipping off the map
        //StartCoroutine(FixBadMovement());

        // if using VR let SDK handle movement
        if (VRTK.VRTK_SDKManager.ValidInstance()) {
            return;
        }
        // Store the input axes.
        float h = CrossPlatformInputManager.GetAxisRaw("Horizontal");
        float v = CrossPlatformInputManager.GetAxisRaw("Vertical");

        // Move the player around the scene.
        Move (h, v);

        // Turn the player to face the mouse cursor.
        Turning ();

        // Animate the player.
        Animating (h, v);
    }
    
    private void FixBadMovement()
    {
        // do this on a timed update to reduce cpu time
        //yield return new WaitForSeconds(fixBadMovementDelay);
    
        if (player.position.y < floor.position.y-10.0f) {
            // for (int i = 0; i < cameraFollowers.Length; i++) {
            //     cameraFollowers[i].enabled = false;
            // }
            //player.position.Set(player.position.x, floor.position.y + 1.0f, player.position.z);
            player.position = new Vector3(player.position.x, floor.position.y + 1.0f, player.position.z);
            playerRigidbody.MovePosition(new Vector3(player.position.x, floor.position.y + 1.0f, player.position.z));
            // for (int i = 0; i < cameraFollowers.Length; i++) {
            //     cameraFollowers[i].enabled = true;
            // }
        }
        else if (player.position.x > levelLimit1.position.x && player.position.z < levelLimit1.position.z) {
            player.position.Set(levelLimit1.position.x - 1.0f, player.position.y, levelLimit1.position.z + 1.0f);
        }
        else if (player.position.x < levelLimit2.position.x && player.position.z < levelLimit2.position.z) {
            player.position.Set(levelLimit2.position.x + 1.0f, player.position.y, levelLimit2.position.z + 1.0f);
        }
        else if (player.position.x > levelLimit3.position.x && player.position.z > levelLimit3.position.z) {
            player.position.Set(levelLimit3.position.x - 1.0f, player.position.y, levelLimit3.position.z - 1.0f);
        }
        else if (player.position.x < levelLimit4.position.x && player.position.z > levelLimit4.position.z) {
            player.position.Set(levelLimit4.position.x + 1.0f, player.position.y, levelLimit4.position.z - 1.0f);
        }
        else if (player.position.y > ceiling.position.y) {
            player.position.Set(player.position.x, floor.position.y + 1.0f, player.position.z);
        }
    }
    
    void Move (float h, float v)
    {
        // Fix any movement outside of level exents
        
        // Set the movement vector based on the axis input.
        movement.Set (h, 0f, v);
        
        // Normalise the movement vector and make it proportional to the speed per second.
        movement = movement.normalized * speed * Time.deltaTime;

        // Move the player to it's current position plus the movement.
        playerRigidbody.MovePosition (transform.position + movement);
    }

    void Turning ()
    {
#if !MOBILE_INPUT
        // Create a ray from the mouse cursor on screen in the direction of the camera.
        Ray camRay = Camera.main.ScreenPointToRay (Input.mousePosition);

        // Create a RaycastHit variable to store information about what was hit by the ray.
        RaycastHit floorHit;

        // Perform the raycast and if it hits something on the floor layer...
        if (Physics.Raycast (camRay, out floorHit, camRayLength, floorMask)) {
            // Create a vector from the player to the point on the floor the raycast from the mouse hit.
            Vector3 playerToMouse = floorHit.point - transform.position;

            // Ensure the vector is entirely along the floor plane.
            playerToMouse.y = 0f;

            // Create a quaternion (rotation) based on looking down the vector from the player to the mouse.
            Quaternion newRotatation = Quaternion.LookRotation (playerToMouse);

            // Set the player's rotation to this new rotation.
            playerRigidbody.MoveRotation (newRotatation);
        }
#else
        Vector3 turnDir = new Vector3(CrossPlatformInputManager.GetAxisRaw("Mouse X") , 0f , CrossPlatformInputManager.GetAxisRaw("Mouse Y"));

        if (turnDir != Vector3.zero)
        {
            // Create a vector from the player to the point on the floor the raycast from the mouse hit.
            Vector3 playerToMouse = (transform.position + turnDir) - transform.position;

            // Ensure the vector is entirely along the floor plane.
            playerToMouse.y = 0f;

            // Create a quaternion (rotation) based on looking down the vector from the player to the mouse.
            Quaternion newRotatation = Quaternion.LookRotation(playerToMouse);

            // Set the player's rotation to this new rotation.
            playerRigidbody.MoveRotation(newRotatation);
        }
#endif
    }


    void Animating (float h, float v)
    {
        // Create a boolean that is true if either of the input axes is non-zero.
        bool walking = h != 0f || v != 0f;

        // Tell the animator whether or not the player is walking.
        anim.SetBool ("IsWalking", walking);
    }
}

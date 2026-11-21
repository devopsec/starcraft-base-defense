using System.Collections;
using System.Collections.Generic;
using UnityEngine;

using UnityEngine;
 
[System.Serializable]
public class SingleUnityLayer
{
    [SerializeField]
    private int m_LayerIndex = 0;
    public int LayerIndex
    {
        get { return m_LayerIndex; }
    }
 
    public void Set(int _layerIndex)
    {
        if (_layerIndex > 0 && _layerIndex < 32)
        {
            m_LayerIndex = _layerIndex;
        }
    }
 
    public int Mask
    {
        get { return 1 << m_LayerIndex; }
    }
}

[System.Serializable]
public class LayerMapping
{
    public SingleUnityLayer layer1;
    public SingleUnityLayer layer2;
}
public class CollisionManager : MonoBehaviour
{
    public LayerMapping[] ignoreCollisionsMapping;

    void Start()
    {
        for (int i = 0; i < ignoreCollisionsMapping.Length; i++) {
            Physics.IgnoreLayerCollision(ignoreCollisionsMapping[0].layer1.LayerIndex, ignoreCollisionsMapping[0].layer2.LayerIndex);   
        }
    }
}
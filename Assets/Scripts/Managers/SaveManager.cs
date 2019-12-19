using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Runtime.Serialization.Formatters.Binary;
using UnityEngine;

[System.Serializable]
public class SaveGameObject
{
    public int high_score;
    
    public SaveGameObject()
    {
        high_score = HighScoreManager.high_score;
    }
}

public class SaveManager : MonoBehaviour
{
    private void Awake()
    {
        loadGame();
    }
    
    private void OnDestroy()
    {
        saveGame();
    }

    public void saveGame()
    {
        if (!Directory.Exists(Application.persistentDataPath)) {
            Directory.CreateDirectory(Application.persistentDataPath);
        }

        SaveGameObject save = new SaveGameObject();

        BinaryFormatter bf = new BinaryFormatter();
        FileStream file = File.Create(Application.persistentDataPath + "/save.bin");
        bf.Serialize(file, save);
        file.Close();
    }

    public void loadGame()
    {
        if (!File.Exists(Application.persistentDataPath + "/save.bin")) {
            HighScoreManager.high_score = 0;
            return;
        }
        
        BinaryFormatter bf = new BinaryFormatter();
        FileStream file = File.Open(Application.persistentDataPath + "/save.bin", FileMode.Open);
        SaveGameObject save = (SaveGameObject)bf.Deserialize(file);
        file.Close();

        HighScoreManager.high_score = save.high_score;
    }
}
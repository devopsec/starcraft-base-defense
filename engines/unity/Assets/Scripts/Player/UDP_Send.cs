using System;
using System.Net;
using System.Net.Sockets;
using System.Text;

using UnityEngine; 

public class UDP_Send : MonoBehaviour
{
    private const String Address = "192.168.0.255";
    private const int port = 1337;
    private UdpClient   UdpBroadcast;
    //private IPAddress broadcastAddress;
    //private IPEndPoint  endPoint;

    private byte[]      send_buffer; 


	public UDP_Send()
	{

        UdpBroadcast = new UdpClient();
        UdpBroadcast.Client.Bind(new IPEndPoint(IPAddress.Any, port));

    }

    public void Send_Command()
    {
        //String command = "{\"DeviceId\":\"2\",\"Shoot\":1,\"data\":42}";
        String command = "{\"DeviceId\":\"2\",\"Color\":0,\"Length\":3,\"Pattern\":1,\"Shoot\":1}"; //white
        //String command = "{\"DeviceId\":\"2\",\"Color\":1,\"Length\":3,\"Pattern\":1,\"Shoot\":1}"; //red
        //String command = "{\"DeviceId\":\"2\",\"Color\":2,\"Length\":3,\"Pattern\":1,\"Shoot\":1}"; // blue

        send_buffer = Encoding.UTF8.GetBytes(command);
        UdpBroadcast.Send(send_buffer, send_buffer.Length, Address, port);

        Console.WriteLine("Sent Data: " + command);
    }

    public void Send_Stop()
    {
        String command = "{\"DeviceId\":\"2\",\"Color\":0,\"Length\":3,\"Pattern\":0,\"Shoot\":0}";

        send_buffer = Encoding.UTF8.GetBytes(command);
        UdpBroadcast.Send(send_buffer, send_buffer.Length, Address, port);

        Console.WriteLine("Sent Data: " + command);
    }
}

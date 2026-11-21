using Stride.CommunityToolkit.Engine;
using Stride.CommunityToolkit.Extensions;
using Stride.CommunityToolkit.Games;
using Stride.CommunityToolkit.Helpers;
using Stride.CommunityToolkit.Rendering;
using Stride.CommunityToolkit.Rendering.Compositing;
using Stride.CommunityToolkit.Rendering.ProceduralModels;
using Stride.Core.Mathematics;
using Stride.Engine;
using StarcraftBaseDefense.Adapter;

// Code-only Stride game: no asset pipeline needed. The Zig core owns the rules;
// GameHost / EnemyView / PlayerController are the thin Stride adapter.
Game game = new Game();
game.Run(start: scene => Start(game, scene));
game.Dispose();

static void Start(Game game, Scene scene)
{
    game.AddGraphicsCompositor().AddCleanUIStage();
    game.AddDirectionalLight();
    var ground = Shapes.Box(game, "Ground", new Vector3(40, 0.2f, 40), Color.DarkOliveGreen);
    ground.Transform.Position = new Vector3(0, -0.1f, 0);
    scene.Entities.Add(ground);

    var player = new Entity("Player", new Vector3(0, 1.6f, 0));
    var controller = new PlayerController();
    player.Add(controller);
    scene.Entities.Add(player);

    // The toolkit camera becomes a child of the player so the view follows movement and aiming.
    Entity camera = game.Add3DCamera();
    scene.Entities.Remove(camera);
    camera.Transform.Position = Vector3.Zero;
    camera.Transform.Rotation = Quaternion.Identity;
    player.AddChild(camera);

    var host = new Entity("GameHost");
    host.Add(new GameHost { Player = controller });
    scene.Entities.Add(host);
}

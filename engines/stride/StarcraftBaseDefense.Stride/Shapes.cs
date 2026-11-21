using Stride.Core.Mathematics;
using Stride.Engine;
using Stride.Rendering;
using Stride.Rendering.Materials;
using Stride.Rendering.Materials.ComputeColors;
using Stride.Rendering.ProceduralModels;

namespace StarcraftBaseDefense.Adapter;

/// <summary>Builds colored primitive entities with Stride's built-in procedural models (no asset pipeline).</summary>
public static class Shapes
{
    public static Entity Box(Game game, string name, Vector3 size, Color color)
    {
        return Make(game, name, new CubeProceduralModel { Size = size }, color);
    }

    public static Entity Capsule(Game game, string name, float length, float radius, Color color)
    {
        return Make(game, name, new CapsuleProceduralModel { Length = length, Radius = radius }, color);
    }

    private static Entity Make(Game game, string name, PrimitiveProceduralModelBase procedural, Color color)
    {
        Model model = new ProceduralModelDescriptor(procedural).GenerateModel(game.Services);
        model.Materials.Add(new MaterialInstance(Colored(game, color)));
        var entity = new Entity(name);
        entity.Add(new ModelComponent(model));
        return entity;
    }

    private static Material Colored(Game game, Color color)
    {
        var descriptor = new MaterialDescriptor
        {
            Attributes =
            {
                Diffuse = new MaterialDiffuseMapFeature(new ComputeColor(color)),
                DiffuseModel = new MaterialDiffuseLambertModelFeature(),
            },
        };
        return Material.New(game.GraphicsDevice, descriptor);
    }
}

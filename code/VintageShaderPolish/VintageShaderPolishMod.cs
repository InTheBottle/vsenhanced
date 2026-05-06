using HarmonyLib;
using System.Reflection;
using Vintagestory.API.Client;
using Vintagestory.API.Common;
using Vintagestory.API.MathTools;
using Vintagestory.Client.NoObf;

namespace VintageShaderPolish;

public sealed class VintageShaderPolishMod : ModSystem
{
    private const string HarmonyId = "ronni.vintageshaderpolish";
    private Harmony? harmony;

    public override bool ShouldLoad(EnumAppSide side) => side == EnumAppSide.Client;

    public override void StartClientSide(ICoreClientAPI api)
    {
        RealCloudShadowState.SetApi(api);
        harmony = new Harmony(HarmonyId);
        harmony.PatchAll(typeof(VintageShaderPolishMod).Assembly);
        RealCloudShadowState.TryPatchCloudRendererMap(harmony);
        api.Logger.Notification("Vintage Shader Polish: sun-relative cloud shadow shader bridge enabled.");
    }

    public override void Dispose()
    {
        harmony?.UnpatchAll(HarmonyId);
        harmony = null;
    }
}

internal static class RealCloudShadowState
{
    private const int CloudMapTextureUnit = 12;
    private static bool disabledAfterError;
    private static bool loggedMissingState;
    private static bool loggedFirstTexture;
    private static bool loggedFirstWidth;
    private static bool loggedFirstOffset;
    private static bool loggedFirstBind;
    private static bool loggedFirstRendererCapture;
    private static ICoreClientAPI? api;
    private static readonly FieldInfo? CloudRendererTextureMapField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "TextureMap");
    private static readonly FieldInfo? CloudRendererOffsetField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "offset");
    private static readonly FieldInfo? CloudRendererCloudTileLengthField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererBase"), "CloudTileLength");

    internal static int CloudMapTextureId { get; set; }
    internal static float CloudMapWidth { get; set; }
    internal static Vec3f? CloudOffset { get; set; }

    internal static void SetApi(ICoreClientAPI clientApi) => api = clientApi;

    internal static void TryPatchCloudRendererMap(Harmony harmony)
    {
        MethodInfo? renderMethod = AccessTools.Method(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "OnRenderFrame");
        MethodInfo? postfixMethod = typeof(RealCloudShadowState).GetMethod(nameof(CaptureCloudRendererMapPostfix), BindingFlags.Static | BindingFlags.NonPublic);
        if (renderMethod == null || postfixMethod == null)
        {
            api?.Logger.Warning("Vintage Shader Polish: could not find FluffyClouds.CloudRendererMap.OnRenderFrame for cloud shadow capture.");
            return;
        }

        harmony.Patch(renderMethod, postfix: new HarmonyMethod(postfixMethod));
        api?.Logger.Notification("Vintage Shader Polish: patched FluffyClouds.CloudRendererMap for real cloud shadow capture.");
    }

    private static void CaptureCloudRendererMapPostfix(object __instance)
    {
        if (api == null || CloudRendererTextureMapField == null || CloudRendererOffsetField == null || CloudRendererCloudTileLengthField == null)
        {
            return;
        }

        int textureMap = (int)(CloudRendererTextureMapField.GetValue(__instance) ?? 0);
        int cloudTileLength = (int)(CloudRendererCloudTileLengthField.GetValue(__instance) ?? 0);
        var offset = CloudRendererOffsetField.GetValue(__instance) as Vec3f;

        if (textureMap > 0)
        {
            SetCloudMapTexture(textureMap, "FluffyClouds.CloudRendererMap.TextureMap");
        }

        if (cloudTileLength > 1)
        {
            SetCloudMapWidth(cloudTileLength, "FluffyClouds.CloudRendererBase.CloudTileLength");
        }

        if (offset != null)
        {
            SetCloudOffset(offset, "FluffyClouds.CloudRendererMap.offset");
        }

        if (!loggedFirstRendererCapture)
        {
            loggedFirstRendererCapture = true;
            api.Logger.Notification(
                "Vintage Shader Polish: observed FluffyClouds renderer. tex={0}, width={1}, offset={2}.",
                textureMap,
                cloudTileLength,
                offset == null ? "null" : $"{offset.X}/{offset.Y}/{offset.Z}"
            );
        }
    }

    internal static void SetCloudMapTexture(int textureId, string source)
    {
        CloudMapTextureId = textureId;
        if (!loggedFirstTexture && textureId > 0)
        {
            loggedFirstTexture = true;
            api?.Logger.Notification("Vintage Shader Polish: captured cloud shadow texture {0} from {1}.", textureId, source);
        }
    }

    internal static void SetCloudMapWidth(float width, string source)
    {
        CloudMapWidth = width;
        if (!loggedFirstWidth && width > 1f)
        {
            loggedFirstWidth = true;
            api?.Logger.Notification("Vintage Shader Polish: captured cloud shadow width {0} from {1}.", width, source);
        }
    }

    internal static void SetCloudOffset(Vec3f value, string source)
    {
        CloudOffset = value;
        if (!loggedFirstOffset)
        {
            loggedFirstOffset = true;
            api?.Logger.Notification("Vintage Shader Polish: captured cloud shadow offset {0}/{1}/{2} from {3}.", value.X, value.Y, value.Z, source);
        }
    }

    internal static void TryApply(ShaderProgramBase shader)
    {
        if (disabledAfterError || api == null)
        {
            return;
        }

        bool wantsCloudMap = shader.HasUniform("realCloudShadowMap");
        bool wantsLightDirection = shader.HasUniform("realCloudShadowLightDir");
        if (!wantsCloudMap && !wantsLightDirection)
        {
            return;
        }

        try
        {
            Vec3f sun = GetUpwardSunDirection();
            if (wantsLightDirection)
            {
                shader.Uniform("realCloudShadowLightDir", sun);
            }
            if (shader.HasUniform("realCloudShadowDaylight"))
            {
                shader.Uniform("realCloudShadowDaylight", api.World.Calendar.DayLightStrength);
            }

            if (!wantsCloudMap)
            {
                return;
            }

            if (CloudMapTextureId <= 0 || CloudMapWidth <= 1f || CloudOffset is not { } offset)
            {
                if (!loggedMissingState && shader.PassName is "chunkopaque" or "chunktopsoil" or "chunktransparent" or "chunkliquid")
                {
                    loggedMissingState = true;
                    api.Logger.Notification(
                        "Vintage Shader Polish: cloud shadow bind waiting. pass={0}, tex={1}, width={2}, offset={3}.",
                        shader.PassName,
                        CloudMapTextureId,
                        CloudMapWidth,
                        CloudOffset == null ? "null" : $"{CloudOffset.X}/{CloudOffset.Y}/{CloudOffset.Z}"
                    );
                }
                return;
            }

            shader.BindTexture2D("realCloudShadowMap", CloudMapTextureId, CloudMapTextureUnit);
            if (shader.HasUniform("realCloudShadowMapWidth"))
            {
                shader.Uniform("realCloudShadowMapWidth", CloudMapWidth);
            }
            if (shader.HasUniform("realCloudShadowOffset"))
            {
                shader.Uniform("realCloudShadowOffset", offset);
            }
            if (shader.HasUniform("realCloudShadowStrength"))
            {
                shader.Uniform("realCloudShadowStrength", 1.35f);
            }
            if (wantsLightDirection)
            {
                shader.Uniform("realCloudShadowLightDir", sun);
            }
            if (shader.HasUniform("realCloudShadowDaylight"))
            {
                shader.Uniform("realCloudShadowDaylight", api.World.Calendar.DayLightStrength);
            }

            if (!loggedFirstBind)
            {
                loggedFirstBind = true;
                api.Logger.Notification(
                    "Vintage Shader Polish: bound sun-relative cloud shadow map to shader {0}. tex={1}, width={2}, offset={3}/{4}/{5}, sun={6}/{7}/{8}.",
                    shader.PassName,
                    CloudMapTextureId,
                    CloudMapWidth,
                    offset.X,
                    offset.Y,
                    offset.Z,
                    sun.X,
                    sun.Y,
                    sun.Z
                );
            }
        }
        catch (System.Exception ex)
        {
            disabledAfterError = true;
            api?.Logger.Error("Vintage Shader Polish: disabled cloud shadow bind after error: {0}", ex);
        }
    }

    private static Vec3f GetUpwardSunDirection()
    {
        Vec3f sun = api!.World.Calendar.SunPositionNormalized;
        return sun.Y < 0 ? new Vec3f(-sun.X, -sun.Y, -sun.Z) : sun;
    }
}

[HarmonyPatch(typeof(ShaderProgramCloudvolumetric), "set_CloudMap2D")]
internal static class CaptureCloudMapTexturePatch
{
    private static void Postfix(int value) => RealCloudShadowState.SetCloudMapTexture(value, "cloudvolumetric.CloudMap2D");
}

[HarmonyPatch(typeof(ShaderProgramCloudvolumetric), "set_CloudMapWidth")]
internal static class CaptureCloudMapWidthPatch
{
    private static void Postfix(float value) => RealCloudShadowState.SetCloudMapWidth(value, "cloudvolumetric.CloudMapWidth");
}

[HarmonyPatch(typeof(ShaderProgramCloudvolumetric), "set_CloudOffset")]
internal static class CaptureCloudOffsetPatch
{
    private static void Postfix(Vec3f value) => RealCloudShadowState.SetCloudOffset(value, "cloudvolumetric.CloudOffset");
}

[HarmonyPatch(typeof(ShaderProgramCloudmap), "set_Width")]
internal static class CaptureCloudmapWidthPatch
{
    private static void Postfix(float value) => RealCloudShadowState.SetCloudMapWidth(value, "cloudmap.Width");
}

[HarmonyPatch(typeof(ShaderProgramCloudmap), "set_MapOffset")]
internal static class CaptureCloudmapOffsetPatch
{
    private static void Postfix(Vec3f value) => RealCloudShadowState.SetCloudOffset(value, "cloudmap.MapOffset");
}

[HarmonyPatch(typeof(ShaderProgramBase), nameof(ShaderProgramBase.Use))]
internal static class BindRealCloudShadowPatch
{
    private static void Postfix(ShaderProgramBase __instance) => RealCloudShadowState.TryApply(__instance);
}

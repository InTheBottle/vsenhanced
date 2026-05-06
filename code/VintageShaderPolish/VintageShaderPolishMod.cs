using HarmonyLib;
using OpenTK.Graphics.OpenGL;
using System;
using System.Collections.Generic;
using System.Reflection;
using Vintagestory.API.Client;
using Vintagestory.API.Common;
using Vintagestory.API.Config;
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
        RealCloudShadowState.Reset();
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
    private const int CloudMapTextureUnit = 15;
    private static bool disabledAfterError;
    private static bool loggedMissingState;
    private static bool loggedFirstTexture;
    private static bool loggedFirstWidth;
    private static bool loggedFirstOffset;
    private static bool loggedFirstBind;
    private static bool loggedFirstRendererCapture;
    private static bool loggedFirstWetness;
    private static float smoothedDropletIntensity;
    private static long lastWetnessUpdateMs;
    private static readonly HashSet<string> loggedBindPasses = new();
    private static ICoreClientAPI? api;
    private static readonly FieldInfo? CloudRendererTextureMapField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "TextureMap");
    private static readonly FieldInfo? CloudRendererOffsetField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "offset");
    private static readonly FieldInfo? CloudRendererCloudTileLengthField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererBase"), "CloudTileLength");

    internal static int CloudMapTextureId { get; set; }
    internal static float CloudMapWidth { get; set; }
    internal static Vec3f? CloudOffset { get; set; }

    internal static void Reset()
    {
        disabledAfterError = false;
        loggedMissingState = false;
        loggedFirstTexture = false;
        loggedFirstWidth = false;
        loggedFirstOffset = false;
        loggedFirstBind = false;
        loggedFirstRendererCapture = false;
        loggedFirstWetness = false;
        smoothedDropletIntensity = 0f;
        lastWetnessUpdateMs = 0;
        CloudMapTextureId = 0;
        CloudMapWidth = 0f;
        CloudOffset = null;
        loggedBindPasses.Clear();
    }

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

        bool wantsCloudSampler = shader.HasUniform("realCloudShadowMap");
        bool wantsCloudMapWidth = shader.HasUniform("realCloudShadowMapWidth");
        bool wantsCloudOffset = shader.HasUniform("realCloudShadowOffset");
        bool wantsCloudStrength = shader.HasUniform("realCloudShadowStrength");
        bool wantsLightDirection = shader.HasUniform("realCloudShadowLightDir");
        bool wantsDaylight = shader.HasUniform("realCloudShadowDaylight");
        bool wantsMoonlight = shader.HasUniform("realMoonLightStrength");
        bool wantsWetness = shader.HasUniform("dropletIntensity");
        bool wantsCloudState = wantsCloudSampler || wantsCloudMapWidth || wantsCloudOffset || wantsCloudStrength || wantsLightDirection || wantsDaylight || wantsMoonlight;
        if (!wantsCloudState && !wantsWetness)
        {
            return;
        }

        try
        {
            if (wantsWetness)
            {
                shader.Uniform("dropletIntensity", GetDropletIntensity());
            }

            if (!wantsCloudState)
            {
                return;
            }

            Vec3f sun = GetUpwardSunDirection();
            float daylight = GetCelestialLightStrength();
            float moonlight = GetMoonLightStrength();
            bool shouldBindCloudMap = ShouldBindCloudMap(shader, wantsCloudSampler);
            bool hasCloudState = CloudMapTextureId > 0 && CloudMapWidth > 1f && CloudOffset is { };

            if (wantsLightDirection)
            {
                shader.Uniform("realCloudShadowLightDir", sun);
            }
            if (wantsDaylight)
            {
                shader.Uniform("realCloudShadowDaylight", daylight);
            }
            if (wantsMoonlight)
            {
                shader.Uniform("realMoonLightStrength", moonlight);
            }
            if (wantsCloudMapWidth)
            {
                shader.Uniform("realCloudShadowMapWidth", hasCloudState ? CloudMapWidth : 0f);
            }
            if (wantsCloudStrength)
            {
                shader.Uniform("realCloudShadowStrength", hasCloudState ? 1.45f : 0f);
            }

            if (!hasCloudState)
            {
                if (!loggedMissingState && IsTerrainPass(shader.PassName))
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

            Vec3f offset = CloudOffset!;
            if (wantsCloudOffset)
            {
                shader.Uniform("realCloudShadowOffset", offset);
            }

            if (!shouldBindCloudMap)
            {
                return;
            }

            BindCloudMap(shader);

            if (wantsCloudMapWidth)
            {
                shader.Uniform("realCloudShadowMapWidth", CloudMapWidth);
            }
            if (wantsLightDirection)
            {
                shader.Uniform("realCloudShadowLightDir", sun);
            }
            if (wantsDaylight)
            {
                shader.Uniform("realCloudShadowDaylight", daylight);
            }
            if (wantsMoonlight)
            {
                shader.Uniform("realMoonLightStrength", moonlight);
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

            if (IsTerrainPass(shader.PassName) && loggedBindPasses.Add(shader.PassName))
            {
                api.Logger.Notification(
                    "Vintage Shader Polish: cloud shadow map bound to terrain shader {0}. tex={1}, width={2}, unit={3}.",
                    shader.PassName,
                    CloudMapTextureId,
                    CloudMapWidth,
                    CloudMapTextureUnit
                );
            }
        }
        catch (System.Exception ex)
        {
            disabledAfterError = true;
            api?.Logger.Error("Vintage Shader Polish: disabled cloud shadow bind after error: {0}", ex);
        }
    }

    private static bool IsTerrainPass(string passName) => passName is "chunkopaque" or "chunktopsoil" or "chunktransparent" or "chunkliquid";

    private static bool ShouldBindCloudMap(ShaderProgramBase shader, bool hasSampler)
    {
        if (!hasSampler)
        {
            return false;
        }

        return IsTerrainPass(shader.PassName) || shader.PassName == "godrays";
    }

    private static void BindCloudMap(ShaderProgramBase shader)
    {
        int previousActiveTexture = GL.GetInteger(GetPName.ActiveTexture);
        shader.BindTexture2D("realCloudShadowMap", CloudMapTextureId, CloudMapTextureUnit);
        GL.ActiveTexture((TextureUnit)previousActiveTexture);
    }

    private static Vec3f GetUpwardSunDirection()
    {
        Vec3f sun = api!.World.Calendar.SunPositionNormalized;
        return sun.Y < 0 ? new Vec3f(-sun.X, -sun.Y, -sun.Z) : sun;
    }

    private static float GetCelestialLightStrength()
    {
        Vec3f sun = api!.World.Calendar.SunPositionNormalized;
        float daylight = api.World.Calendar.DayLightStrength;
        if (sun.Y >= 0f)
        {
            return daylight;
        }

        float moonlight = GetMoonLightStrength();
        return Math.Max(daylight, moonlight);
    }

    private static float GetMoonLightStrength()
    {
        Vec3f sun = api!.World.Calendar.SunPositionNormalized;
        if (sun.Y >= 0f)
        {
            return 0f;
        }

        float moonElevation = Math.Clamp(-sun.Y, 0f, 1f);
        return SmoothStep(Math.Clamp((moonElevation - 0.03f) / 0.42f, 0f, 1f)) * 0.42f;
    }

    private static float SmoothStep(float value) => value * value * (3f - 2f * value);

    private static float GetDropletIntensity()
    {
        if (api?.World.Player?.Entity?.Pos == null)
        {
            return 0f;
        }

        float target = 0f;
        try
        {
            ClimateCondition? climate = api.World.BlockAccessor.GetClimateAt(
                api.World.Player.Entity.Pos.AsBlockPos,
                EnumGetClimateMode.NowValues,
                api.World.Calendar.TotalDays
            );
            float precipitation = Math.Clamp((climate?.Rainfall ?? 0f) - 0.08f, 0f, 1f) / 0.62f;
            float distance = GlobalConstants.CurrentDistanceToRainfallClient;
            float exposure = distance <= 0f ? 1f : Math.Clamp(1f - distance / 12f, 0f, 1f);
            target = MathF.Pow(Math.Clamp(precipitation * exposure, 0f, 1f), 0.65f) * 1.45f;
        }
        catch
        {
            target = 0f;
        }

        long now = api.ElapsedMilliseconds;
        if (lastWetnessUpdateMs == 0)
        {
            lastWetnessUpdateMs = now;
            smoothedDropletIntensity = target;
        }
        else
        {
            float dt = Math.Clamp((now - lastWetnessUpdateMs) / 1000f, 0f, 0.25f);
            lastWetnessUpdateMs = now;
            float response = target > smoothedDropletIntensity ? 4.0f : 0.45f;
            smoothedDropletIntensity += (target - smoothedDropletIntensity) * Math.Clamp(dt * response, 0f, 1f);
        }

        if (!loggedFirstWetness && smoothedDropletIntensity > 0.01f)
        {
            loggedFirstWetness = true;
            api.Logger.Notification("Vintage Shader Polish: weather wetness active, dropletIntensity={0:0.00}.", smoothedDropletIntensity);
        }

        return smoothedDropletIntensity;
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

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
        TerrainHeightMapState.Reset();
        TerrainHeightMapState.SetApi(api);
        harmony = new Harmony(HarmonyId);
        harmony.PatchAll(typeof(VintageShaderPolishMod).Assembly);
        RealCloudShadowState.TryPatchCloudRendererMap(harmony);
        RealCloudShadowState.LocateWeatherSystem();
        api.Logger.Notification("Vintage Shader Polish: sun-relative cloud shadow shader bridge enabled.");
    }

    public override void Dispose()
    {
        TerrainHeightMapState.Dispose();
        harmony?.UnpatchAll(HarmonyId);
        harmony = null;
    }
}

// Low-resolution terrain heightmap centered on the player. Used by godrays.fsh
// as a shadow occluder source for samples that fall outside the engine's shadow
// cascade -- without this, distant tall geometry (mountains) registers as fully
// lit at low sun angles because the cascade is shallow and elongated.
internal static class TerrainHeightMapState
{
    private const int Resolution = 256;
    private const float MetersPerTexel = 2.0f;
    private const float WorldSize = Resolution * MetersPerTexel;
    private const int RecenterStep = 16;

    private static int textureId;
    private static int originX;
    private static int originZ;
    private static int lastSnappedX = int.MinValue;
    private static int lastSnappedZ = int.MinValue;
    private static bool initialized;
    private static readonly float[] heightData = new float[Resolution * Resolution];
    private static bool loggedFirstUpload;
    private static ICoreClientAPI? api;

    internal static int TextureId => textureId;
    internal static float OriginX => originX;
    internal static float OriginZ => originZ;
    internal static float WorldSizeMeters => WorldSize;

    internal static void SetApi(ICoreClientAPI clientApi) => api = clientApi;

    internal static void Reset()
    {
        Dispose();
        lastSnappedX = int.MinValue;
        lastSnappedZ = int.MinValue;
        initialized = false;
        loggedFirstUpload = false;
    }

    internal static void Dispose()
    {
        if (textureId != 0)
        {
            try { GL.DeleteTexture(textureId); } catch { }
            textureId = 0;
        }
    }

    internal static bool TryUpdate()
    {
        if (api == null || api.World?.BlockAccessor == null) return initialized;
        var camPos = api.World.Player?.Entity?.CameraPos;
        if (camPos == null) return initialized;

        int camX = (int)Math.Floor(camPos.X);
        int camZ = (int)Math.Floor(camPos.Z);
        int snapX = (camX / RecenterStep) * RecenterStep;
        int snapZ = (camZ / RecenterStep) * RecenterStep;
        if (initialized && snapX == lastSnappedX && snapZ == lastSnappedZ) return true;

        int radius = (int)(WorldSize * 0.5f);
        originX = snapX - radius;
        originZ = snapZ - radius;
        lastSnappedX = snapX;
        lastSnappedZ = snapZ;

        var ba = api.World.BlockAccessor;
        for (int j = 0; j < Resolution; j++)
        {
            int worldZ = originZ + (int)(j * MetersPerTexel);
            int row = j * Resolution;
            for (int i = 0; i < Resolution; i++)
            {
                int worldX = originX + (int)(i * MetersPerTexel);
                int h = ba.GetRainMapHeightAt(worldX, worldZ);
                heightData[row + i] = h > 0 ? h + 0.5f : -1.0f;
            }
        }

        int prevActive = GL.GetInteger(GetPName.ActiveTexture);
        int prevBound = GL.GetInteger(GetPName.TextureBinding2D);
        try
        {
            if (textureId == 0)
            {
                textureId = GL.GenTexture();
                GL.BindTexture(TextureTarget.Texture2D, textureId);
                GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.R32f, Resolution, Resolution, 0, PixelFormat.Red, PixelType.Float, heightData);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Linear);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Linear);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureWrapS, (int)TextureWrapMode.ClampToEdge);
                GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureWrapT, (int)TextureWrapMode.ClampToEdge);
            }
            else
            {
                GL.BindTexture(TextureTarget.Texture2D, textureId);
                GL.TexSubImage2D(TextureTarget.Texture2D, 0, 0, 0, Resolution, Resolution, PixelFormat.Red, PixelType.Float, heightData);
            }
        }
        finally
        {
            GL.BindTexture(TextureTarget.Texture2D, prevBound);
            GL.ActiveTexture((TextureUnit)prevActive);
        }

        initialized = true;
        if (!loggedFirstUpload)
        {
            loggedFirstUpload = true;
            api.Logger.Notification("Vintage Shader Polish: terrain heightmap uploaded. tex={0}, origin={1}/{2}, size={3}m.", textureId, originX, originZ, WorldSize);
        }
        return true;
    }
}

internal static class RealCloudShadowState
{
    private const int CloudMapTextureUnit = 15;
    private const int SceneDepthTextureUnit = 11;
    private const int ShadowMapFarTextureUnit = 12;
    private const int ShadowMapNearTextureUnit = 13;
    private const int TerrainHeightMapTextureUnit = 14;
    private const int ConsecutiveErrorThreshold = 8;
    private static bool disabledAfterError;
    private static int consecutiveErrors;
    private static bool loggedMissingState;
    private static bool loggedFirstTexture;
    private static bool loggedFirstWidth;
    private static bool loggedFirstOffset;
    private static bool loggedFirstBind;
    private static bool loggedFirstRendererCapture;
    private static bool loggedFirstGodrayRaymarch;
    private static bool loggedFirstGodraySamplers;
    private static readonly HashSet<string> loggedBindPasses = new();
    private static ICoreClientAPI? api;
    private static readonly FieldInfo? CloudRendererTextureMapField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "TextureMap");
    private static readonly FieldInfo? CloudRendererOffsetField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererMap"), "offset");
    private static readonly FieldInfo? CloudRendererCloudTileLengthField = AccessTools.Field(AccessTools.TypeByName("FluffyClouds.CloudRendererBase"), "CloudTileLength");
    // VSEssentials.WeatherSystemClient.BlendedWeatherData.PrecIntensity, accessed via reflection.
    private static readonly Type? WeatherSystemClientType = AccessTools.TypeByName("Vintagestory.GameContent.WeatherSystemClient");
    private static readonly PropertyInfo? BlendedWeatherDataProp = WeatherSystemClientType != null ? AccessTools.Property(WeatherSystemClientType, "BlendedWeatherData") : null;
    private static readonly FieldInfo? PrecIntensityField = AccessTools.Field(AccessTools.TypeByName("Vintagestory.GameContent.WeatherDataSnapshot"), "PrecIntensity");
    private static object? weatherSystemClient;

    internal static int CloudMapTextureId { get; set; }
    internal static float CloudMapWidth { get; set; }
    internal static Vec3f? CloudOffset { get; set; }

    internal static void Reset()
    {
        disabledAfterError = false;
        consecutiveErrors = 0;
        loggedMissingState = false;
        loggedFirstTexture = false;
        loggedFirstWidth = false;
        loggedFirstOffset = false;
        loggedFirstBind = false;
        loggedFirstRendererCapture = false;
        loggedFirstGodrayRaymarch = false;
        loggedFirstGodraySamplers = false;
        CloudMapTextureId = 0;
        CloudMapWidth = 0f;
        CloudOffset = null;
        loggedBindPasses.Clear();
    }

    internal static void SetApi(ICoreClientAPI clientApi) => api = clientApi;

    internal static void LocateWeatherSystem()
    {
        if (api == null || WeatherSystemClientType == null) return;
        foreach (var sys in api.ModLoader.Systems)
        {
            if (WeatherSystemClientType.IsInstanceOfType(sys))
            {
                weatherSystemClient = sys;
                api.Logger.Notification("Vintage Shader Polish: located WeatherSystemClient for precipitation-driven shader effects.");
                return;
            }
        }
        api.Logger.Warning("Vintage Shader Polish: WeatherSystemClient not found; wet-block effects disabled.");
    }

    private static float GetPrecIntensity()
    {
        if (weatherSystemClient == null || BlendedWeatherDataProp == null || PrecIntensityField == null) return 0f;
        try
        {
            object? snapshot = BlendedWeatherDataProp.GetValue(weatherSystemClient);
            if (snapshot == null) return 0f;
            return (float)(PrecIntensityField.GetValue(snapshot) ?? 0f);
        }
        catch
        {
            return 0f;
        }
    }

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

        // World/Calendar briefly null during shader reload pre-level-init.
        if (api.World == null || api.World.Calendar == null)
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
        bool wantsInvProjection = shader.HasUniform("invProjectionMatrix");
        bool wantsInvModelView = shader.HasUniform("invModelViewMatrix");
        bool wantsCameraWorldPos = shader.HasUniform("realCameraWorldPos");
        bool wantsCameraWorldPosition = shader.HasUniform("cameraWorldPosition");
        bool wantsSunLight = shader.HasUniform("sunLightStrength");
        bool wantsDayLight = shader.HasUniform("dayLightStrength");
        bool wantsShadowIntensity = shader.HasUniform("shadowIntensity");
        bool wantsFlatFog = shader.HasUniform("flatFogDensity");
        bool wantsPlayerWaterDepth = shader.HasUniform("playerWaterDepth");
        bool wantsFogColor = shader.HasUniform("fogColor");
        bool wantsPrecIntensity = shader.HasUniform("precIntensity");
        bool wantsTrueSunPos = shader.HasUniform("trueSunPos");
        bool wantsRayState = wantsInvProjection || wantsInvModelView || wantsCameraWorldPos;
        bool wantsVolumetricState = wantsCameraWorldPosition || wantsSunLight || wantsDayLight || wantsShadowIntensity || wantsFlatFog || wantsPlayerWaterDepth || wantsFogColor;
        bool wantsCloudState = wantsCloudSampler || wantsCloudMapWidth || wantsCloudOffset || wantsCloudStrength || wantsLightDirection || wantsDaylight || wantsMoonlight || wantsRayState || wantsVolumetricState || wantsPrecIntensity || wantsTrueSunPos;
        if (!wantsCloudState)
        {
            return;
        }

        try
        {
            Vec3f sun = GetUpwardSunDirection();
            float daylight = GetCelestialLightStrength();
            float moonlight = GetMoonLightStrength();
            bool shouldBindCloudMap = ShouldBindCloudMap(shader, wantsCloudSampler);
            bool hasCloudState = CloudMapTextureId > 0 && CloudMapWidth > 1f && CloudOffset is { };
            ApplyVolumetricUniforms(shader, wantsCameraWorldPosition, wantsSunLight, wantsDayLight, wantsShadowIntensity, wantsFlatFog, wantsPlayerWaterDepth, wantsFogColor);

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
            if (wantsPrecIntensity)
            {
                shader.Uniform("precIntensity", GetPrecIntensity());
            }
            if (wantsTrueSunPos)
            {
                shader.Uniform("trueSunPos", api.World.Calendar.SunPositionNormalized);
            }
            if (wantsRayState)
            {
                ApplyRaymarchUniforms(shader, wantsInvProjection, wantsInvModelView, wantsCameraWorldPos);
                if (!loggedFirstGodrayRaymarch && shader.PassName == "godrays")
                {
                    loggedFirstGodrayRaymarch = true;
                    api.Logger.Notification("Vintage Shader Polish: godray raymarch uniforms bound. invProjection={0}, invModelView={1}, cameraWorldPos={2}.", wantsInvProjection, wantsInvModelView, wantsCameraWorldPos);
                }
            }
            if (shader.PassName == "godrays")
            {
                ApplyGodraySamplers(shader);
            }
            // Width=0 short-circuits the volumetric path on passes (godrays) we deliberately skip binding.
            bool feedCloudState = hasCloudState && shouldBindCloudMap;
            if (wantsCloudMapWidth)
            {
                shader.Uniform("realCloudShadowMapWidth", feedCloudState ? CloudMapWidth : 0f);
            }
            if (wantsCloudStrength)
            {
                shader.Uniform("realCloudShadowStrength", feedCloudState ? 1.45f : 0f);
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

            consecutiveErrors = 0;
        }
        catch (System.Exception ex)
        {
            consecutiveErrors++;
            if (consecutiveErrors >= ConsecutiveErrorThreshold)
            {
                disabledAfterError = true;
                api?.Logger.Error("Vintage Shader Polish: disabled cloud shadow bind after {0} consecutive errors: {1}", consecutiveErrors, ex);
            }
            else if (consecutiveErrors == 1)
            {
                api?.Logger.Warning("Vintage Shader Polish: transient cloud shadow bind error (will retry): {0}", ex.Message);
            }
        }
    }

    private static bool IsTerrainPass(string passName) => passName is "chunkopaque" or "chunktopsoil" or "chunktransparent" or "chunkliquid";

    private static bool ShouldBindCloudMap(ShaderProgramBase shader, bool hasSampler)
    {
        if (!hasSampler)
        {
            return false;
        }

        // Cloud-sampler bind on godrays causes a GL_INVALID_OPERATION flood; terrain only.
        return IsTerrainPass(shader.PassName);
    }

    private static void BindCloudMap(ShaderProgramBase shader)
    {
        int previousActiveTexture = GL.GetInteger(GetPName.ActiveTexture);
        shader.BindTexture2D("realCloudShadowMap", CloudMapTextureId, CloudMapTextureUnit);
        GL.ActiveTexture((TextureUnit)previousActiveTexture);
    }

    private static void ApplyRaymarchUniforms(ShaderProgramBase shader, bool wantsInvProjection, bool wantsInvModelView, bool wantsCameraWorldPos)
    {
        if (wantsInvProjection)
        {
            shader.UniformMatrix("invProjectionMatrix", ToFloatMatrix(Mat4f.Invert(Mat4f.Create(), api!.Render.CurrentProjectionMatrix)));
        }

        if (wantsInvModelView)
        {
            shader.UniformMatrix("invModelViewMatrix", ToFloatMatrix(Mat4f.Invert(Mat4f.Create(), api!.Render.CameraMatrixOriginf)));
        }

        if (wantsCameraWorldPos && api!.World.Player?.Entity?.CameraPos != null)
        {
            Vec3d cameraPos = api.World.Player.Entity.CameraPos;
            shader.Uniform("realCameraWorldPos", (float)cameraPos.X, (float)cameraPos.Y, (float)cameraPos.Z);
        }
    }

    private static void ApplyVolumetricUniforms(ShaderProgramBase shader, bool wantsCameraWorldPosition, bool wantsSunLight, bool wantsDayLight, bool wantsShadowIntensity, bool wantsFlatFog, bool wantsPlayerWaterDepth, bool wantsFogColor)
    {
        if (wantsCameraWorldPosition)
        {
            float[] invModelView = Mat4f.Invert(Mat4f.Create(), api!.Render.CameraMatrixOriginf);
            Vec4f origin = new(0f, 0f, 0f, 1f);
            Vec4f cameraWorld = new();
            Mat4f.MulWithVec4(invModelView, origin, cameraWorld);
            shader.Uniform("cameraWorldPosition", cameraWorld);
        }

        if (wantsSunLight)
        {
            shader.Uniform("sunLightStrength", api!.World.Calendar.SunLightStrength);
        }
        if (wantsDayLight)
        {
            shader.Uniform("dayLightStrength", api!.World.Calendar.DayLightStrength);
        }
        if (wantsShadowIntensity)
        {
            shader.Uniform("shadowIntensity", GetDropShadowIntensity());
        }
        if (wantsFlatFog)
        {
            shader.Uniform("flatFogDensity", api!.Ambient.BlendedFlatFogDensity);
        }
        if (wantsPlayerWaterDepth)
        {
            shader.Uniform("playerWaterDepth", 0f);
        }
        if (wantsFogColor)
        {
            shader.Uniform("fogColor", api!.Ambient.BlendedFogColor);
        }
    }

    // Bind scene depth + cascaded shadow maps + matrices for world-space godray raymarching.
    private static void ApplyGodraySamplers(ShaderProgramBase shader)
    {
        if (api == null) return;
        var fbs = api.Render.FrameBuffers;
        if (fbs == null) return;

        FrameBufferRef? primary = fbs.Count > 0 ? fbs[0] : null;
        FrameBufferRef? shadowFar = fbs.Count > 11 ? fbs[11] : null;
        FrameBufferRef? shadowNear = fbs.Count > 12 ? fbs[12] : null;

        if (shader.HasUniform("sceneDepthTex") && primary != null && primary.DepthTextureId > 0)
        {
            int prevActive = GL.GetInteger(GetPName.ActiveTexture);
            shader.BindTexture2D("sceneDepthTex", primary.DepthTextureId, SceneDepthTextureUnit);
            GL.ActiveTexture((TextureUnit)prevActive);
        }
        if (shader.HasUniform("shadowMapFar") && shadowFar != null && shadowFar.DepthTextureId > 0)
        {
            int prevActive = GL.GetInteger(GetPName.ActiveTexture);
            shader.BindTexture2D("shadowMapFar", shadowFar.DepthTextureId, ShadowMapFarTextureUnit);
            GL.ActiveTexture((TextureUnit)prevActive);
        }
        if (shader.HasUniform("shadowMapNear") && shadowNear != null && shadowNear.DepthTextureId > 0)
        {
            int prevActive = GL.GetInteger(GetPName.ActiveTexture);
            shader.BindTexture2D("shadowMapNear", shadowNear.DepthTextureId, ShadowMapNearTextureUnit);
            GL.ActiveTexture((TextureUnit)prevActive);
        }

        var u = api.Render.ShaderUniforms;
        if (shader.HasUniform("toShadowMapSpaceMatrixFar") && u.ToShadowMapSpaceMatrixFar != null)
        {
            shader.UniformMatrix("toShadowMapSpaceMatrixFar", u.ToShadowMapSpaceMatrixFar);
        }
        if (shader.HasUniform("toShadowMapSpaceMatrixNear") && u.ToShadowMapSpaceMatrixNear != null)
        {
            shader.UniformMatrix("toShadowMapSpaceMatrixNear", u.ToShadowMapSpaceMatrixNear);
        }
        if (shader.HasUniform("shadowRangeFar"))
        {
            shader.Uniform("shadowRangeFar", u.ShadowRangeFar);
        }
        if (shader.HasUniform("shadowRangeNear"))
        {
            shader.Uniform("shadowRangeNear", u.ShadowRangeNear);
        }
        if (shader.HasUniform("shadowZExtendFar"))
        {
            shader.Uniform("shadowZExtendFar", u.ShadowZExtendFar);
        }
        if (shader.HasUniform("shadowZExtendNear"))
        {
            shader.Uniform("shadowZExtendNear", u.ShadowZExtendNear);
        }
        if (shader.HasUniform("shadowMapWidthInv") && shadowFar != null && shadowFar.Width > 0)
        {
            shader.Uniform("shadowMapWidthInv", 1f / shadowFar.Width);
        }
        if (shader.HasUniform("shadowMapHeightInv") && shadowFar != null && shadowFar.Height > 0)
        {
            shader.Uniform("shadowMapHeightInv", 1f / shadowFar.Height);
        }

        if (shader.HasUniform("terrainHeightMap"))
        {
            TerrainHeightMapState.TryUpdate();
            if (TerrainHeightMapState.TextureId > 0 && api.World.Player?.Entity?.CameraPos is { } camPos)
            {
                int prevActive = GL.GetInteger(GetPName.ActiveTexture);
                shader.BindTexture2D("terrainHeightMap", TerrainHeightMapState.TextureId, TerrainHeightMapTextureUnit);
                GL.ActiveTexture((TextureUnit)prevActive);
                float relX = TerrainHeightMapState.OriginX - (float)camPos.X;
                float relZ = TerrainHeightMapState.OriginZ - (float)camPos.Z;
                if (shader.HasUniform("heightMapOriginRel"))
                {
                    shader.Uniform("heightMapOriginRel", relX, relZ);
                }
                if (shader.HasUniform("heightMapWorldSize"))
                {
                    shader.Uniform("heightMapWorldSize", TerrainHeightMapState.WorldSizeMeters);
                }
                if (shader.HasUniform("heightMapCameraY"))
                {
                    shader.Uniform("heightMapCameraY", (float)camPos.Y);
                }
            }
        }

        if (!loggedFirstGodraySamplers)
        {
            loggedFirstGodraySamplers = true;
            api.Logger.Notification(
                "Vintage Shader Polish: godrays world-space samplers bound. sceneDepth={0}, shadowFar={1}, shadowNear={2}, shadowFarSize={3}x{4}.",
                primary?.DepthTextureId ?? 0,
                shadowFar?.DepthTextureId ?? 0,
                shadowNear?.DepthTextureId ?? 0,
                shadowFar?.Width ?? 0,
                shadowFar?.Height ?? 0);
        }
    }

    private static float[] ToFloatMatrix(float[] matrix)
    {
        float[] result = new float[matrix.Length];
        for (int i = 0; i < matrix.Length; i++)
        {
            result[i] = (float)matrix[i];
        }

        return result;
    }

    private static float GetDropShadowIntensity()
    {
        FieldInfo? field = typeof(AmbientManager).GetField("DropShadowIntensity", BindingFlags.Instance | BindingFlags.NonPublic);
        return field?.GetValue(api!.Ambient) is float value ? value : 1f;
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

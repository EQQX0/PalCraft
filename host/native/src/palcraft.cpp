// PalCraft native half: lives inside Palworld (D3D11), draws Minecraft's layers into each finished frame
// with depth occlusion, publishes what Palworld rendered, and handles the F8 hand-over.
//
// Compositing shader, frame-slot selection and the shared-memory protocol come from Minecraft Ring's
// er-bridge (MIT, justbustin & siddoff); the D3D11 plumbing, scene-depth finder and frame tags are new.
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <emmintrin.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "MinHook.h"
#include "protocol.h"

namespace pc {

// ---------------------------------------------------------------------------------------------------
// Paths, log

static char g_modDir[MAX_PATH];
static char g_runtime[MAX_PATH];
static bool g_dev = false;
static CRITICAL_SECTION g_logLock;

static void log(const char* fmt, ...) {
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%spalcraft_native.log", g_runtime);
    EnterCriticalSection(&g_logLock);
    FILE* f = fopen(path, "ab");
    if (f) {
        SYSTEMTIME t;
        GetLocalTime(&t);
        fprintf(f, "%02d:%02d:%02d.%03d ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fputc('\n', f);
        fclose(f);
    }
    LeaveCriticalSection(&g_logLock);
}

static uint64_t now_ms() { return GetTickCount64(); }

static void make_dirs(const char* path) {
    char tmp[MAX_PATH];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char* p = tmp + 3; *p; p++) {
        if (*p == '\\' || *p == '/') {
            char c = *p;
            *p = 0;
            CreateDirectoryA(tmp, nullptr);
            *p = c;
        }
    }
}

// The same rule as main.lua: runtime_dir.txt next to the mod wins, else %LOCALAPPDATA%\PalCraft\runtime\.
static void resolve_paths(HMODULE self) {
    GetModuleFileNameA(self, g_modDir, MAX_PATH);
    char* slash = strrchr(g_modDir, '\\');
    if (slash) slash[1] = 0;
    char txt[MAX_PATH];
    snprintf(txt, sizeof(txt), "%sruntime_dir.txt", g_modDir);
    g_runtime[0] = 0;
    FILE* f = fopen(txt, "rb");
    if (f) {
        size_t n = fread(g_runtime, 1, MAX_PATH - 2, f);
        fclose(f);
        while (n && (g_runtime[n - 1] == '\r' || g_runtime[n - 1] == '\n' || g_runtime[n - 1] == ' ')) n--;
        g_runtime[n] = 0;
    }
    if (!g_runtime[0]) {
        char local[MAX_PATH] = ".";
        GetEnvironmentVariableA("LOCALAPPDATA", local, MAX_PATH);
        snprintf(g_runtime, sizeof(g_runtime), "%s\\PalCraft\\runtime\\", local);
    }
    size_t n = strlen(g_runtime);
    if (n && g_runtime[n - 1] != '\\' && g_runtime[n - 1] != '/') strcat(g_runtime, "\\");
    make_dirs(g_runtime);
    char flag[MAX_PATH];
    snprintf(flag, sizeof(flag), "%sdev_enabled", g_runtime);
    g_dev = GetFileAttributesA(flag) != INVALID_FILE_ATTRIBUTES;
}

// ---------------------------------------------------------------------------------------------------
// Shared files

static uint8_t* g_shm = nullptr;
static uint8_t* g_frames = nullptr;
static uint64_t g_framesTriedMs = 0;

template <typename T>
static T& at(uint8_t* base, uint32_t off) {
    return *(T*)(base + off);
}
#define HDR(T, field) at<T>(g_shm, PC_OFF_HEADER + PC_HEADER_##field)
#define ST(T, field) at<T>(g_shm, PC_OFF_STATE + PC_GAME_STATE_##field)

static bool shm_open() {
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%sbridge.shm", g_runtime);
    HANDLE f = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) {
        log("shm: cannot open %s (%lu)", path, GetLastError());
        return false;
    }
    HANDLE m = CreateFileMappingA(f, nullptr, PAGE_READWRITE, 0, PC_CONST_SHM_SIZE, nullptr);
    CloseHandle(f);
    if (!m) {
        log("shm: mapping failed (%lu)", GetLastError());
        return false;
    }
    g_shm = (uint8_t*)MapViewOfFile(m, FILE_MAP_ALL_ACCESS, 0, 0, PC_CONST_SHM_SIZE);
    CloseHandle(m);
    if (!g_shm) return false;
    if (HDR(uint32_t, MAGIC) != PC_CONST_MAGIC || HDR(uint32_t, VERSION) != PC_CONST_VERSION) {
        memset(g_shm, 0, PC_OFF_RAYS);
        HDR(uint32_t, SIZE) = PC_CONST_SHM_SIZE;
        HDR(uint32_t, VERSION) = PC_CONST_VERSION;
        HDR(uint32_t, MAGIC) = PC_CONST_MAGIC;
    }
    // A fresh Palworld session: nothing Palworld said last time is true any more.
    memset(g_shm + PC_OFF_STATE, 0, PC_SIZE_STATE);
    memset(g_shm + PC_OFF_LUASTATE, 0, PC_SIZE_LUASTATE);
    HDR(uint32_t, HOST_PID) = GetCurrentProcessId();
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32 | ft.dwLowDateTime) / 10000 - 11644473600000ull;
    HDR(uint64_t, HOST_START_MS) = t;
    log("shm: %s mapped", path);
    return true;
}

static const uint64_t kSlotSize = (uint64_t)PC_CONST_FRAME_HDR + (uint64_t)PC_CONST_FRAME_MAX_W * PC_CONST_FRAME_MAX_H * 16u;
static const uint64_t kFramesSize = PC_CONST_FRAMES_OFF_SLOTS + PC_CONST_FRAME_SLOTS * kSlotSize;

static bool frames_open() {
    if (g_frames) return true;
    uint64_t now = now_ms();
    if (now - g_framesTriedMs < 2000) return false;
    g_framesTriedMs = now;
    char path[MAX_PATH];
    snprintf(path, sizeof(path), "%sframes.shm", g_runtime);
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;  // Minecraft creates it
    LARGE_INTEGER size;
    if (!GetFileSizeEx(f, &size) || (uint64_t)size.QuadPart < kFramesSize) {
        CloseHandle(f);
        return false;
    }
    HANDLE m = CreateFileMappingA(f, nullptr, PAGE_READONLY, 0, 0, nullptr);
    CloseHandle(f);
    if (!m) return false;
    uint8_t* p = (uint8_t*)MapViewOfFile(m, FILE_MAP_READ, 0, 0, (SIZE_T)kFramesSize);
    CloseHandle(m);
    if (!p) return false;
    if (at<uint32_t>(p, PC_FRAMES_HEADER_MAGIC) != PC_CONST_FRAMES_MAGIC ||
        at<uint32_t>(p, PC_FRAMES_HEADER_VERSION) != PC_CONST_FRAMES_VERSION) {
        UnmapViewOfFile(p);
        return false;
    }
    g_frames = p;
    log("frames: frames.shm mapped");
    return true;
}

static uint8_t* slot_ptr(uint32_t i) { return g_frames + PC_CONST_FRAMES_OFF_SLOTS + (uint64_t)i * kSlotSize; }

// Copies a seqlocked region; false if the writer never left it alone.
static bool seq_read(uint32_t off, void* dst, uint32_t size) {
    for (int i = 0; i < 16; i++) {
        uint32_t s1 = at<volatile uint32_t>(g_shm, off);
        if (s1 & 1) {
            YieldProcessor();
            continue;
        }
        memcpy(dst, g_shm + off, size);
        _mm_mfence();
        if (at<volatile uint32_t>(g_shm, off) == s1) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------------------------------
// Game objects and the frame's bookkeeping (all touched on Palworld's RHI thread only)

static IDXGISwapChain* g_sc = nullptr;
static ID3D11Device* g_devc = nullptr;
static ID3D11DeviceContext* g_ctx = nullptr;
static HWND g_hwnd = nullptr;
static volatile LONG g_stopped = 0;
static bool g_internal = false;  // our own D3D calls: the hooks stay out of the way
static bool g_failed = false;
static uint64_t g_presents = 0;

template <typename T>
static void rel(T*& p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

// --- scene depth: the full-screen depth buffer with the most draws this frame
struct DepthCand {
    ID3D11Texture2D* tex;  // AddRef'd
    UINT w, h;
    DXGI_FORMAT fmt;
    UINT bind;
    UINT draws;
    bool cleared;
    float vpW, vpH;
};
static const int kMaxCands = 24;
static DepthCand g_cands[kMaxCands];
static int g_candCount = 0;
static int g_cur = -1;  // candidate bound right now
static ID3D11DepthStencilView* g_lastDsv = nullptr;  // not owned: only compared
static int g_lastDsvCand = -1;
static float g_vpW = 0, g_vpH = 0;

static ID3D11Texture2D* g_depthTex = nullptr;  // chosen last frame (AddRef'd)
static ID3D11Texture2D* g_depthCopy = nullptr;  // when the game's texture cannot be sampled
static ID3D11ShaderResourceView* g_depthSrv = nullptr;
static UINT g_depthW = 0, g_depthH = 0;
static float g_depthVpW = 0, g_depthVpH = 0;
static bool g_depthIsCopy = false;

// --- frame tag: which Lua tick rendered the frame being presented
static int g_tag = -1;
static uint64_t g_tagPresent = 0;

static void cands_reset() {
    for (int i = 0; i < g_candCount; i++) rel(g_cands[i].tex);
    g_candCount = 0;
    g_cur = -1;
    g_lastDsv = nullptr;
    g_lastDsvCand = -1;
}

static int cand_for(ID3D11DepthStencilView* dsv) {
    if (!dsv) return -1;
    if (dsv == g_lastDsv) return g_lastDsvCand;
    ID3D11Resource* res = nullptr;
    dsv->GetResource(&res);
    int found = -1;
    if (res) {
        for (int i = 0; i < g_candCount; i++)
            if ((ID3D11Resource*)g_cands[i].tex == res) found = i;
        if (found < 0 && g_candCount < kMaxCands) {
            ID3D11Texture2D* tex = nullptr;
            if (SUCCEEDED(res->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&tex))) {
                D3D11_TEXTURE2D_DESC d;
                tex->GetDesc(&d);
                if (d.SampleDesc.Count == 1 && d.ArraySize == 1 && d.Width >= 320) {
                    DepthCand& c = g_cands[g_candCount];
                    c = {};
                    c.tex = tex;
                    c.w = d.Width;
                    c.h = d.Height;
                    c.fmt = d.Format;
                    c.bind = d.BindFlags;
                    found = g_candCount++;
                } else {
                    tex->Release();
                }
            }
        }
        res->Release();
    }
    g_lastDsv = dsv;
    g_lastDsvCand = found;
    return found;
}

typedef void(STDMETHODCALLTYPE* SetTargets_t)(ID3D11DeviceContext*, UINT, ID3D11RenderTargetView* const*,
                                               ID3D11DepthStencilView*);
typedef void(STDMETHODCALLTYPE* ClearDepth_t)(ID3D11DeviceContext*, ID3D11DepthStencilView*, UINT, FLOAT, UINT8);
typedef void(STDMETHODCALLTYPE* DrawII_t)(ID3D11DeviceContext*, UINT, UINT, UINT, INT, UINT);
typedef void(STDMETHODCALLTYPE* Viewports_t)(ID3D11DeviceContext*, UINT, const D3D11_VIEWPORT*);
static SetTargets_t oSetTargets = nullptr;
static ClearDepth_t oClearDepth = nullptr;
static DrawII_t oDrawII = nullptr;
static Viewports_t oViewports = nullptr;

static void STDMETHODCALLTYPE hkSetTargets(ID3D11DeviceContext* c, UINT n, ID3D11RenderTargetView* const* rtvs,
                                           ID3D11DepthStencilView* dsv) {
    if (c == g_ctx && !g_internal) g_cur = cand_for(dsv);
    oSetTargets(c, n, rtvs, dsv);
}

static void STDMETHODCALLTYPE hkClearDepth(ID3D11DeviceContext* c, ID3D11DepthStencilView* dsv, UINT flags, FLOAT depth,
                                           UINT8 stencil) {
    if (c == g_ctx && !g_internal && (flags & D3D11_CLEAR_DEPTH)) {
        int i = cand_for(dsv);
        if (i >= 0) g_cands[i].cleared = true;
    }
    oClearDepth(c, dsv, flags, depth, stencil);
}

static void STDMETHODCALLTYPE hkDrawII(ID3D11DeviceContext* c, UINT a, UINT b, UINT d, INT e, UINT f) {
    if (g_cur >= 0 && c == g_ctx) {
        DepthCand& k = g_cands[g_cur];
        k.draws++;
        k.vpW = g_vpW;
        k.vpH = g_vpH;
    }
    oDrawII(c, a, b, d, e, f);
}

static void STDMETHODCALLTYPE hkViewports(ID3D11DeviceContext* c, UINT n, const D3D11_VIEWPORT* v) {
    if (c == g_ctx && !g_internal && n && v) {
        if (v[0].Height == (float)PC_CONST_TAG_H && v[0].Width >= (float)PC_CONST_TAG_BASE_W &&
            v[0].Width < (float)(PC_CONST_TAG_BASE_W + PC_CONST_TAG_COUNT)) {
            g_tag = (int)v[0].Width - (int)PC_CONST_TAG_BASE_W;
            g_tagPresent = g_presents;
        }
        g_vpW = v[0].Width;
        g_vpH = v[0].Height;
    }
    oViewports(c, n, v);
}

static DXGI_FORMAT depth_srv_format(DXGI_FORMAT f) {
    switch (f) {
        case DXGI_FORMAT_R32G8X24_TYPELESS:
        case DXGI_FORMAT_D32_FLOAT_S8X24_UINT: return DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS;
        case DXGI_FORMAT_R24G8_TYPELESS:
        case DXGI_FORMAT_D24_UNORM_S8_UINT: return DXGI_FORMAT_R24_UNORM_X8_TYPELESS;
        case DXGI_FORMAT_R32_TYPELESS:
        case DXGI_FORMAT_D32_FLOAT: return DXGI_FORMAT_R32_FLOAT;
        case DXGI_FORMAT_R16_TYPELESS:
        case DXGI_FORMAT_D16_UNORM: return DXGI_FORMAT_R16_UNORM;
        default: return DXGI_FORMAT_UNKNOWN;
    }
}

static DXGI_FORMAT depth_typeless(DXGI_FORMAT f) {
    switch (f) {
        case DXGI_FORMAT_D32_FLOAT_S8X24_UINT: return DXGI_FORMAT_R32G8X24_TYPELESS;
        case DXGI_FORMAT_D24_UNORM_S8_UINT: return DXGI_FORMAT_R24G8_TYPELESS;
        case DXGI_FORMAT_D32_FLOAT: return DXGI_FORMAT_R32_TYPELESS;
        case DXGI_FORMAT_D16_UNORM: return DXGI_FORMAT_R16_TYPELESS;
        default: return f;
    }
}

// Picks this frame's scene depth and makes it samplable. Called at Present, before the table is reset.
static void adopt_depth(UINT bbW, UINT bbH) {
    int best = -1;
    float bbAspect = (float)bbW / (float)bbH;
    for (int i = 0; i < g_candCount; i++) {
        DepthCand& c = g_cands[i];
        if (c.draws < 20 || depth_srv_format(c.fmt) == DXGI_FORMAT_UNKNOWN) continue;
        float w = c.vpW > 0 && c.vpW <= c.w ? c.vpW : (float)c.w;
        float h = c.vpH > 0 && c.vpH <= c.h ? c.vpH : (float)c.h;
        float aspect = w / h;
        if (aspect < bbAspect * 0.97f || aspect > bbAspect * 1.03f) continue;
        if (w < bbW * 0.25f) continue;
        if (best < 0 || c.draws > g_cands[best].draws) best = i;
    }
    if (best < 0) return;  // keep last frame's choice
    DepthCand& c = g_cands[best];
    float vw = c.vpW > 0 && c.vpW <= c.w ? c.vpW : (float)c.w;
    float vh = c.vpH > 0 && c.vpH <= c.h ? c.vpH : (float)c.h;
    if (c.tex != g_depthTex) {
        rel(g_depthSrv);
        rel(g_depthCopy);
        rel(g_depthTex);
        g_depthTex = c.tex;
        g_depthTex->AddRef();
        g_depthW = c.w;
        g_depthH = c.h;
        g_depthIsCopy = !(c.bind & D3D11_BIND_SHADER_RESOURCE);
        ID3D11Texture2D* src = g_depthTex;
        if (g_depthIsCopy) {
            D3D11_TEXTURE2D_DESC d;
            g_depthTex->GetDesc(&d);
            d.Format = depth_typeless(d.Format);
            d.BindFlags = D3D11_BIND_SHADER_RESOURCE;
            d.Usage = D3D11_USAGE_DEFAULT;
            d.CPUAccessFlags = 0;
            d.MiscFlags = 0;
            if (FAILED(g_devc->CreateTexture2D(&d, nullptr, &g_depthCopy))) {
                rel(g_depthTex);
                return;
            }
            src = g_depthCopy;
        }
        D3D11_SHADER_RESOURCE_VIEW_DESC sd = {};
        sd.Format = depth_srv_format(c.fmt);
        sd.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
        sd.Texture2D.MipLevels = 1;
        HRESULT hr = g_devc->CreateShaderResourceView(src, &sd, &g_depthSrv);
        log("depth: scene depth %p %ux%u format %u, %u draws, view %.0fx%.0f, %s (%08lx)", (void*)c.tex, c.w, c.h,
            (unsigned)c.fmt, c.draws, vw, vh, g_depthIsCopy ? "copied" : "sampled in place", (unsigned long)hr);
        if (FAILED(hr)) {
            rel(g_depthCopy);
            rel(g_depthTex);
            return;
        }
    }
    g_depthVpW = vw;
    g_depthVpH = vh;
}

// ---------------------------------------------------------------------------------------------------
// Compositor

static const char* kShader = R"(
Texture2D<float4> tWorld : register(t0);
Texture2D<float>  tMcDepth : register(t1);
Texture2D<float4> tGui : register(t2);
Texture2D<float>  tHostDepth : register(t3);
Texture2D<float4> tLight : register(t4);  // Palworld's frame blurred to ~1/64: local light (blur passes: their source)
Texture2D<float4> tHaze : register(t5);   // ~1/8: the scenery behind a block, for distance haze
Texture2D<float4> tHand : register(t6);   // Minecraft's hand and screen effects (lit, never occluded)
SamplerState sPoint : register(s0);
SamplerState sLinear : register(s1);
cbuffer Params : register(b0) {
    float mcNear; float mcFar; float hostNear; float depthScaleX;
    float depthScaleY; float useDepth; float debugView; float bias;
    float relight; float lightGain; float lightMin; float fogStrength;
    float fogStart; float fogEnd; float tintAmount; float testPattern;
    float handLayer; float worldLayer; float pad1; float pad2;
};
struct VSOut { float4 pos : SV_Position; float2 uv : TEXCOORD0; };
VSOut VS(uint id : SV_VertexID) {
    VSOut o;
    float2 uv = float2((id << 1) & 2, id & 2);
    o.pos = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    o.uv = uv;
    return o;
}
float linMc(float d) {
    float z = d * 2 - 1;
    return 2 * mcNear * mcFar / (mcFar + mcNear - z * (mcFar - mcNear));
}
// Unreal: reversed Z with the far plane at infinity, so depth = near / distance.
float linHost(float d) { return hostNear / max(d, 1e-7); }
float4 PSDown(VSOut i) : SV_Target {
    float2 size;
    tLight.GetDimensions(size.x, size.y);
    float2 texel = 1.0 / size;
    float4 acc = 0;
    [unroll] for (int y = 0; y < 4; y++)
        [unroll] for (int x = 0; x < 4; x++)
            acc += tLight.SampleLevel(sLinear, i.uv + (float2(x, y) - 1.5) * 2.0 * texel, 0);
    return acc / 16.0;
}
float3 lightAt(float2 uv) {
    float3 env = tLight.SampleLevel(sLinear, uv, 0).rgb;
    float lum = dot(env, float3(0.299, 0.587, 0.114));
    float3 tint = saturate(env / max(lum, 1e-3) * 0.5);
    float k = clamp(lightMin + lum * lightGain, 0.0, 1.15);
    return k * lerp(float3(1, 1, 1), tint * 2.0, tintAmount);
}
float4 PS(VSOut i) : SV_Target {
    if (testPattern > 0.5) {
        if (i.uv.x > 0.25 || i.uv.y > 0.25) return 0;
        float c = fmod(floor(i.uv.x * 64) + floor(i.uv.y * 64), 2);
        return float4(0.6 * c, 0.2, 0.6 * (1 - c), 1) * 0.6;
    }
    float2 uvMc = float2(i.uv.x, 1 - i.uv.y);   // Minecraft rows are bottom-up
    float hd = tHostDepth.SampleLevel(sPoint, i.uv * float2(depthScaleX, depthScaleY), 0);
    if (debugView > 0.5) return float4(frac(linHost(hd) / 10).xxx, 1);   // 10 m depth bands
    float4 world = worldLayer > 0.5 ? tWorld.SampleLevel(sPoint, uvMc, 0) : 0;
    float md = tMcDepth.SampleLevel(sPoint, uvMc, 0);
    if (world.a > 0 && md < 1.0) {
        float mc = linMc(md);
        if (useDepth > 0.5 && mc > linHost(hd) + bias + mc * 0.004) world = 0;
        if (relight > 0.5) world.rgb *= lightAt(i.uv);
        float f = saturate((mc - fogStart) / max(fogEnd - fogStart, 1.0)) * fogStrength;
        if (f > 0 && relight > 0.5) {
            float3 behind = tHaze.SampleLevel(sLinear, i.uv, 0).rgb;
            world.rgb = lerp(world.rgb, behind * world.a, f);
        }
    }
    float4 hand = handLayer > 0.5 ? tHand.SampleLevel(sPoint, uvMc, 0) : 0;
    if (hand.a > 0 && relight > 0.5) hand.rgb *= lightAt(i.uv);
    float4 scene = hand + world * (1 - hand.a);
    float4 gui = tGui.SampleLevel(sPoint, uvMc, 0);
    return gui + scene * (1 - gui.a);
}
)";

struct Params {
    float mcNear, mcFar, hostNear, depthScaleX;
    float depthScaleY, useDepth, debugView, bias;
    float relight, lightGain, lightMin, fogStrength;
    float fogStart, fogEnd, tintAmount, testPattern;
    float handLayer, worldLayer, pad1, pad2;
};

static ID3D11VertexShader* g_vs = nullptr;
static ID3D11PixelShader* g_ps = nullptr;
static ID3D11PixelShader* g_psDown = nullptr;
static ID3D11Buffer* g_cb = nullptr;
static ID3D11SamplerState* g_sampPoint = nullptr;
static ID3D11SamplerState* g_sampLinear = nullptr;
static ID3D11BlendState* g_blend = nullptr;
static ID3D11BlendState* g_blendOff = nullptr;
static ID3D11RasterizerState* g_raster = nullptr;
static ID3D11DepthStencilState* g_dss = nullptr;

// Minecraft's layers: two sets, so a frame torn by the writer is never shown.
static const int kLayers = 4;  // world BGRA8, depth R32F, HUD BGRA8, hand BGRA8
static ID3D11Texture2D* g_tex[2][kLayers] = {};
static ID3D11ShaderResourceView* g_texSrv[2][kLayers] = {};
static UINT g_texW = 0, g_texH = 0;
static int g_front = 0;
static bool g_haveFrame = false, g_frontHand = false;
static uint64_t g_lastUploaded = 0;
static float g_frameNear = 0.05f, g_frameFar = 1000.0f;

// Palworld's finished frame and two blurs of it
static ID3D11Texture2D* g_sceneCopy = nullptr;
static ID3D11ShaderResourceView* g_sceneSrv = nullptr;
static ID3D11Texture2D* g_down[2] = {};
static ID3D11ShaderResourceView* g_downSrv[2] = {};
static ID3D11RenderTargetView* g_downRtv[2] = {};
static UINT g_downW[2] = {}, g_downH[2] = {};
static UINT g_sceneW = 0, g_sceneH = 0;
static DXGI_FORMAT g_sceneFmt = DXGI_FORMAT_UNKNOWN;
static uint64_t g_lastCompositeMs = 0;

static bool init_pipeline() {
    ID3DBlob *vs = nullptr, *ps = nullptr, *pd = nullptr, *err = nullptr;
    size_t n = strlen(kShader);
    if (FAILED(D3DCompile(kShader, n, "palcraft", nullptr, nullptr, "VS", "vs_5_0", 0, 0, &vs, &err)) ||
        FAILED(D3DCompile(kShader, n, "palcraft", nullptr, nullptr, "PS", "ps_5_0", 0, 0, &ps, &err)) ||
        FAILED(D3DCompile(kShader, n, "palcraft", nullptr, nullptr, "PSDown", "ps_5_0", 0, 0, &pd, &err))) {
        log("compositor: shader compile failed: %s", err ? (const char*)err->GetBufferPointer() : "?");
        return false;
    }
    bool ok = SUCCEEDED(g_devc->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, &g_vs)) &&
              SUCCEEDED(g_devc->CreatePixelShader(ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &g_ps)) &&
              SUCCEEDED(g_devc->CreatePixelShader(pd->GetBufferPointer(), pd->GetBufferSize(), nullptr, &g_psDown));
    vs->Release();
    ps->Release();
    pd->Release();
    if (!ok) return false;
    D3D11_BUFFER_DESC bd = {};
    bd.ByteWidth = sizeof(Params);
    bd.Usage = D3D11_USAGE_DYNAMIC;
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    D3D11_SAMPLER_DESC sd = {};
    sd.AddressU = sd.AddressV = sd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sd.MaxLOD = D3D11_FLOAT32_MAX;
    sd.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
    D3D11_SAMPLER_DESC sl = sd;
    sl.Filter = D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT;
    D3D11_BLEND_DESC b = {};
    b.RenderTarget[0].BlendEnable = TRUE;
    b.RenderTarget[0].SrcBlend = D3D11_BLEND_ONE;  // premultiplied alpha
    b.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    b.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    b.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ZERO;
    b.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ONE;
    b.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    b.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_RED | D3D11_COLOR_WRITE_ENABLE_GREEN | D3D11_COLOR_WRITE_ENABLE_BLUE;
    D3D11_BLEND_DESC bo = {};
    bo.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    D3D11_RASTERIZER_DESC r = {};
    r.FillMode = D3D11_FILL_SOLID;
    r.CullMode = D3D11_CULL_NONE;
    r.DepthClipEnable = TRUE;
    D3D11_DEPTH_STENCIL_DESC ds = {};
    ds.DepthEnable = FALSE;
    ds.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ZERO;
    ds.DepthFunc = D3D11_COMPARISON_ALWAYS;
    return SUCCEEDED(g_devc->CreateBuffer(&bd, nullptr, &g_cb)) && SUCCEEDED(g_devc->CreateSamplerState(&sd, &g_sampPoint)) &&
           SUCCEEDED(g_devc->CreateSamplerState(&sl, &g_sampLinear)) && SUCCEEDED(g_devc->CreateBlendState(&b, &g_blend)) &&
           SUCCEEDED(g_devc->CreateBlendState(&bo, &g_blendOff)) && SUCCEEDED(g_devc->CreateRasterizerState(&r, &g_raster)) &&
           SUCCEEDED(g_devc->CreateDepthStencilState(&ds, &g_dss));
}

static void release_scene() {
    rel(g_sceneSrv);
    rel(g_sceneCopy);
    for (int i = 0; i < 2; i++) {
        rel(g_downRtv[i]);
        rel(g_downSrv[i]);
        rel(g_down[i]);
    }
    g_sceneW = g_sceneH = 0;
}

static bool ensure_scene(UINT w, UINT h, DXGI_FORMAT fmt) {
    if (g_sceneCopy && g_sceneW == w && g_sceneH == h && g_sceneFmt == fmt) return true;
    release_scene();
    D3D11_TEXTURE2D_DESC d = {};
    d.Width = w;
    d.Height = h;
    d.MipLevels = d.ArraySize = 1;
    d.Format = fmt;
    d.SampleDesc.Count = 1;
    d.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    if (FAILED(g_devc->CreateTexture2D(&d, nullptr, &g_sceneCopy)) ||
        FAILED(g_devc->CreateShaderResourceView(g_sceneCopy, nullptr, &g_sceneSrv)))
        return false;
    UINT dw = w, dh = h;
    for (int i = 0; i < 2; i++) {
        dw = dw / 8 ? dw / 8 : 1;
        dh = dh / 8 ? dh / 8 : 1;
        d.Width = g_downW[i] = dw;
        d.Height = g_downH[i] = dh;
        d.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        d.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
        if (FAILED(g_devc->CreateTexture2D(&d, nullptr, &g_down[i])) ||
            FAILED(g_devc->CreateShaderResourceView(g_down[i], nullptr, &g_downSrv[i])) ||
            FAILED(g_devc->CreateRenderTargetView(g_down[i], nullptr, &g_downRtv[i])))
            return false;
    }
    g_sceneW = w;
    g_sceneH = h;
    g_sceneFmt = fmt;
    return true;
}

static void release_layers() {
    for (int s = 0; s < 2; s++)
        for (int i = 0; i < kLayers; i++) {
            rel(g_texSrv[s][i]);
            rel(g_tex[s][i]);
        }
    g_texW = g_texH = 0;
    g_haveFrame = false;
}

static bool ensure_layers(UINT w, UINT h) {
    if (g_tex[0][0] && g_texW == w && g_texH == h) return true;
    release_layers();
    D3D11_TEXTURE2D_DESC d = {};
    d.Width = w;
    d.Height = h;
    d.MipLevels = d.ArraySize = 1;
    d.SampleDesc.Count = 1;
    d.Usage = D3D11_USAGE_DYNAMIC;
    d.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    d.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    for (int s = 0; s < 2; s++)
        for (int i = 0; i < kLayers; i++) {
            d.Format = i == 1 ? DXGI_FORMAT_R32_FLOAT : DXGI_FORMAT_B8G8R8A8_UNORM;
            if (FAILED(g_devc->CreateTexture2D(&d, nullptr, &g_tex[s][i])) ||
                FAILED(g_devc->CreateShaderResourceView(g_tex[s][i], nullptr, &g_texSrv[s][i]))) {
                release_layers();
                return false;
            }
        }
    g_texW = w;
    g_texH = h;
    log("compositor: Minecraft layers %ux%u", w, h);
    return true;
}

static uint8_t* pick_slot(uint64_t poseId) {
    uint8_t* best = nullptr;
    for (uint32_t i = 0; i < PC_CONST_FRAME_SLOTS; i++) {
        uint8_t* h = slot_ptr(i);
        if (at<volatile uint32_t>(h, PC_FRAME_HEADER_SEQ) & 1) continue;
        uint32_t w = at<uint32_t>(h, PC_FRAME_HEADER_WIDTH), ht = at<uint32_t>(h, PC_FRAME_HEADER_HEIGHT);
        if (!w || !ht || w > PC_CONST_FRAME_MAX_W || ht > PC_CONST_FRAME_MAX_H) continue;
        uint64_t p = at<uint64_t>(h, PC_FRAME_HEADER_POSE_ID);
        if (p == poseId) return h;
        // Else the newest frame that is not newer than the pose Palworld rendered.
        if (p < poseId && (!best || p > at<uint64_t>(best, PC_FRAME_HEADER_POSE_ID))) best = h;
    }
    return best;
}

// Copies a slot into the back texture set and flips to it. False if Minecraft rewrote the slot meanwhile.
static bool upload_slot(uint8_t* h) {
    uint32_t seq = at<volatile uint32_t>(h, PC_FRAME_HEADER_SEQ);
    if (seq & 1) return false;
    UINT w = at<uint32_t>(h, PC_FRAME_HEADER_WIDTH), ht = at<uint32_t>(h, PC_FRAME_HEADER_HEIGHT);
    if (w != g_texW || ht != g_texH) return false;
    uint32_t flags = at<uint32_t>(h, PC_FRAME_HEADER_FLAGS);
    bool hand = (flags & PC_FRAME_HAND) != 0;
    uint64_t layerBytes = (uint64_t)w * ht * 4;
    const uint8_t* base = h + PC_CONST_FRAME_HDR;
    int back = 1 - g_front;
    for (int i = 0; i < (hand ? 4 : 3); i++) {
        D3D11_MAPPED_SUBRESOURCE m;
        if (FAILED(g_ctx->Map(g_tex[back][i], 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return false;
        const uint8_t* src = base + layerBytes * i;
        if (m.RowPitch == w * 4) {
            memcpy(m.pData, src, (size_t)layerBytes);
        } else {
            for (UINT y = 0; y < ht; y++) memcpy((uint8_t*)m.pData + (size_t)y * m.RowPitch, src + (size_t)y * w * 4, w * 4);
        }
        g_ctx->Unmap(g_tex[back][i], 0);
    }
    _mm_mfence();
    if (at<volatile uint32_t>(h, PC_FRAME_HEADER_SEQ) != seq) return false;
    g_front = back;
    g_frontHand = hand;
    g_frameNear = at<float>(h, PC_FRAME_HEADER_MC_NEAR);
    g_frameFar = at<float>(h, PC_FRAME_HEADER_MC_FAR);
    g_lastUploaded = at<uint64_t>(h, PC_FRAME_HEADER_FRAME_ID);
    g_haveFrame = true;
    return true;
}

// Everything the draw below changes, put back afterwards: Unreal caches the pipeline state it set.
struct SavedState {
    ID3D11RenderTargetView* rtv[8];
    ID3D11DepthStencilView* dsv;
    D3D11_VIEWPORT vp[4];
    UINT vpCount;
    D3D11_RECT sc[4];
    UINT scCount;
    ID3D11RasterizerState* rs;
    ID3D11BlendState* bs;
    FLOAT bf[4];
    UINT mask;
    ID3D11DepthStencilState* dss;
    UINT stencil;
    ID3D11InputLayout* il;
    D3D11_PRIMITIVE_TOPOLOGY topo;
    ID3D11VertexShader* vs;
    ID3D11PixelShader* ps;
    ID3D11GeometryShader* gs;
    ID3D11HullShader* hs;
    ID3D11DomainShader* dsh;
    ID3D11ShaderResourceView* srv[7];
    ID3D11SamplerState* samp[2];
    ID3D11Buffer* cb;
};

static void save_state(SavedState& s) {
    memset(&s, 0, sizeof(s));
    g_ctx->OMGetRenderTargets(8, s.rtv, &s.dsv);
    s.vpCount = 4;
    g_ctx->RSGetViewports(&s.vpCount, s.vp);
    s.scCount = 4;
    g_ctx->RSGetScissorRects(&s.scCount, s.sc);
    g_ctx->RSGetState(&s.rs);
    g_ctx->OMGetBlendState(&s.bs, s.bf, &s.mask);
    g_ctx->OMGetDepthStencilState(&s.dss, &s.stencil);
    g_ctx->IAGetInputLayout(&s.il);
    g_ctx->IAGetPrimitiveTopology(&s.topo);
    g_ctx->VSGetShader(&s.vs, nullptr, nullptr);
    g_ctx->PSGetShader(&s.ps, nullptr, nullptr);
    g_ctx->GSGetShader(&s.gs, nullptr, nullptr);
    g_ctx->HSGetShader(&s.hs, nullptr, nullptr);
    g_ctx->DSGetShader(&s.dsh, nullptr, nullptr);
    g_ctx->PSGetShaderResources(0, 7, s.srv);
    g_ctx->PSGetSamplers(0, 2, s.samp);
    g_ctx->PSGetConstantBuffers(0, 1, &s.cb);
}

static void restore_state(SavedState& s) {
    ID3D11ShaderResourceView* none[7] = {};
    g_ctx->PSSetShaderResources(0, 7, none);
    g_ctx->OMSetRenderTargets(8, s.rtv, s.dsv);
    if (s.vpCount) g_ctx->RSSetViewports(s.vpCount, s.vp);
    g_ctx->RSSetScissorRects(s.scCount, s.scCount ? s.sc : nullptr);
    g_ctx->RSSetState(s.rs);
    g_ctx->OMSetBlendState(s.bs, s.bf, s.mask);
    g_ctx->OMSetDepthStencilState(s.dss, s.stencil);
    g_ctx->IASetInputLayout(s.il);
    g_ctx->IASetPrimitiveTopology(s.topo);
    g_ctx->VSSetShader(s.vs, nullptr, 0);
    g_ctx->PSSetShader(s.ps, nullptr, 0);
    g_ctx->GSSetShader(s.gs, nullptr, 0);
    g_ctx->HSSetShader(s.hs, nullptr, 0);
    g_ctx->DSSetShader(s.dsh, nullptr, 0);
    g_ctx->PSSetShaderResources(0, 7, s.srv);
    g_ctx->PSSetSamplers(0, 2, s.samp);
    g_ctx->PSSetConstantBuffers(0, 1, &s.cb);
    for (auto& p : s.rtv) rel(p);
    rel(s.dsv);
    rel(s.rs);
    rel(s.bs);
    rel(s.dss);
    rel(s.il);
    rel(s.vs);
    rel(s.ps);
    rel(s.gs);
    rel(s.hs);
    rel(s.dsh);
    for (auto& p : s.srv) rel(p);
    for (auto& p : s.samp) rel(p);
    rel(s.cb);
}

static void fullscreen(ID3D11RenderTargetView* rtv, UINT w, UINT h) {
    D3D11_VIEWPORT vp = {0, 0, (float)w, (float)h, 0, 1};
    D3D11_RECT sr = {0, 0, (LONG)w, (LONG)h};
    g_ctx->OMSetRenderTargets(1, &rtv, nullptr);
    g_ctx->RSSetViewports(1, &vp);
    g_ctx->RSSetScissorRects(1, &sr);
}

struct LuaView {  // what the Lua mod last said (a copy of the luastate region)
    uint8_t raw[PC_SIZE_LUASTATE];
    bool fresh;
    template <typename T>
    T get(uint32_t off) const {
        T v;
        memcpy(&v, raw + off, sizeof(T));
        return v;
    }
};

static bool mc_alive() {
    static uint64_t last = 0, lastMs = 0;
    uint64_t hb = HDR(uint64_t, MC_HEARTBEAT);
    uint64_t now = now_ms();
    if (hb != last) {
        last = hb;
        lastMs = now;
    }
    return lastMs && now - lastMs < 2000;
}

static uint32_t g_syncExact = 0, g_syncOlder = 0, g_syncMissing = 0, g_syncUntagged = 0;

static void composite(const LuaView& lua, UINT bbW, UINT bbH) {
    bool test = (HDR(uint32_t, DEBUG_FLAGS) & 1) != 0;
    uint8_t ctrl[PC_SIZE_CONTROL];
    bool haveCtrl = mc_alive() && seq_read(PC_OFF_CONTROL, ctrl, PC_SIZE_CONTROL);
    uint32_t cflags = haveCtrl ? *(uint32_t*)(ctrl + PC_CONTROL_FLAGS) : 0;
    bool mc = haveCtrl && (cflags & PC_CTRL_COMPOSITE) && lua.fresh && frames_open();
    if (!mc) g_haveFrame = false;
    if (!test && !mc) return;
    if (!g_vs) {
        if (!init_pipeline()) {
            log("compositor: pipeline FAILED; compositing off");
            g_failed = true;
            return;
        }
        log("compositor: pipeline ready");
    }

    // Which Minecraft pose did Palworld render this frame with? The frame tag says which Lua tick it was.
    uint64_t poseId = 0;
    if (mc) {
        bool tagged = g_tag >= 0 && g_presents - g_tagPresent < 30;
        if (tagged) poseId = lua.get<uint64_t>(PC_LUA_STATE_POSE_HIST + 8 * (uint32_t)g_tag);
        else {
            poseId = lua.get<uint64_t>(PC_LUA_STATE_APPLIED_POSE);
            g_syncUntagged++;
        }
    }
    uint8_t* slot = mc && poseId ? pick_slot(poseId) : nullptr;
    if (mc) {
        if (slot && at<uint64_t>(slot, PC_FRAME_HEADER_POSE_ID) == poseId) g_syncExact++;
        else if (slot) g_syncOlder++;
        else g_syncMissing++;
        if (g_syncExact + g_syncOlder + g_syncMissing >= 600) {
            log("sync: frames with the presented pose: exact %u, older %u, missing %u (untagged %u)", g_syncExact,
                g_syncOlder, g_syncMissing, g_syncUntagged);
            g_syncExact = g_syncOlder = g_syncMissing = g_syncUntagged = 0;
        }
    }
    // A frame Palworld rendered with its own camera gets the HUD only: blocks would be in the wrong place.
    bool worldLayer = mc && poseId != 0;
    if (slot && at<uint64_t>(slot, PC_FRAME_HEADER_FRAME_ID) != g_lastUploaded) {
        if (!ensure_layers(at<uint32_t>(slot, PC_FRAME_HEADER_WIDTH), at<uint32_t>(slot, PC_FRAME_HEADER_HEIGHT))) {
            g_failed = true;
            return;
        }
        upload_slot(slot);
    }
    if (mc && !g_haveFrame) return;

    ID3D11Texture2D* bb = nullptr;
    if (FAILED(g_sc->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&bb))) return;
    D3D11_TEXTURE2D_DESC bd;
    bb->GetDesc(&bd);
    ID3D11RenderTargetView* bbRtv = nullptr;
    if (bd.SampleDesc.Count != 1 || FAILED(g_devc->CreateRenderTargetView(bb, nullptr, &bbRtv))) {
        bb->Release();
        return;
    }
    bool relight = mc && !(cflags & PC_CTRL_NO_RELIGHT) && ensure_scene(bd.Width, bd.Height, bd.Format);
    bool haveDepth = mc && g_depthSrv != nullptr;

    SavedState saved;
    save_state(saved);
    g_internal = true;

    Params p = {};
    p.mcNear = g_frameNear > 0 ? g_frameNear : 0.05f;
    p.mcFar = g_frameFar > 1 ? g_frameFar : 1000.0f;
    float nearZ = lua.get<float>(PC_LUA_STATE_NEAR_Z);
    p.hostNear = nearZ > 0.001f ? nearZ : 0.1f;
    p.depthScaleX = haveDepth ? g_depthVpW / (float)g_depthW : 1.0f;
    p.depthScaleY = haveDepth ? g_depthVpH / (float)g_depthH : 1.0f;
    p.useDepth = (haveDepth && !(cflags & PC_CTRL_NO_DEPTH_TEST)) ? 1.0f : 0.0f;
    p.debugView = ((cflags & PC_CTRL_DEBUG_DEPTH) && haveDepth) ? 1.0f : 0.0f;
    p.bias = PC_TUNE_DEPTH_BIAS_M;
    p.testPattern = (test && !mc) ? 1.0f : 0.0f;
    p.relight = relight ? 1.0f : 0.0f;
    float lg = haveCtrl ? *(float*)(ctrl + PC_CONTROL_LIGHT_GAIN) : 0, lm = haveCtrl ? *(float*)(ctrl + PC_CONTROL_LIGHT_MIN) : 0,
          fs = haveCtrl ? *(float*)(ctrl + PC_CONTROL_FOG_STRENGTH) : 0;
    p.lightGain = lg > 0 ? lg : PC_TUNE_LIGHT_GAIN;
    p.lightMin = lm > 0 ? lm : PC_TUNE_LIGHT_MIN;
    p.fogStrength = fs > 0 ? fs : PC_TUNE_FOG_STRENGTH;
    p.fogStart = PC_TUNE_FOG_START_M;
    p.fogEnd = PC_TUNE_FOG_END_M;
    p.tintAmount = PC_TUNE_LIGHT_TINT;
    p.handLayer = (worldLayer && g_frontHand) ? 1.0f : 0.0f;
    p.worldLayer = worldLayer ? 1.0f : 0.0f;
    D3D11_MAPPED_SUBRESOURCE m;
    if (SUCCEEDED(g_ctx->Map(g_cb, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) {
        memcpy(m.pData, &p, sizeof(p));
        g_ctx->Unmap(g_cb, 0);
    }

    if (haveDepth && g_depthIsCopy) g_ctx->CopyResource(g_depthCopy, g_depthTex);

    FLOAT bf[4] = {0, 0, 0, 0};
    ID3D11SamplerState* samps[2] = {g_sampPoint, g_sampLinear};
    g_ctx->IASetInputLayout(nullptr);
    g_ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    g_ctx->VSSetShader(g_vs, nullptr, 0);
    g_ctx->GSSetShader(nullptr, nullptr, 0);
    g_ctx->HSSetShader(nullptr, nullptr, 0);
    g_ctx->DSSetShader(nullptr, nullptr, 0);
    g_ctx->RSSetState(g_raster);
    g_ctx->OMSetDepthStencilState(g_dss, 0);
    g_ctx->PSSetSamplers(0, 2, samps);
    g_ctx->PSSetConstantBuffers(0, 1, &g_cb);
    ID3D11ShaderResourceView* none[7] = {};
    if (relight) {
        // Palworld's finished frame, then two 8x box blurs of it.
        g_ctx->CopyResource(g_sceneCopy, bb);
        g_ctx->PSSetShader(g_psDown, nullptr, 0);
        g_ctx->OMSetBlendState(g_blendOff, bf, 0xffffffff);
        ID3D11ShaderResourceView* src[2] = {g_sceneSrv, g_downSrv[0]};
        for (int i = 0; i < 2; i++) {
            g_ctx->PSSetShaderResources(0, 7, none);
            fullscreen(g_downRtv[i], g_downW[i], g_downH[i]);
            g_ctx->PSSetShaderResources(4, 1, &src[i]);
            g_ctx->Draw(3, 0);
        }
    }
    g_ctx->PSSetShaderResources(0, 7, none);
    fullscreen(bbRtv, bd.Width, bd.Height);
    g_ctx->PSSetShader(g_ps, nullptr, 0);
    g_ctx->OMSetBlendState(g_blend, bf, 0xffffffff);
    ID3D11ShaderResourceView* srvs[7] = {};
    if (mc) {
        srvs[0] = g_texSrv[g_front][0];
        srvs[1] = g_texSrv[g_front][1];
        srvs[2] = g_texSrv[g_front][2];
        srvs[3] = haveDepth ? g_depthSrv : nullptr;
        srvs[4] = relight ? g_downSrv[1] : nullptr;
        srvs[5] = relight ? g_downSrv[0] : nullptr;
        srvs[6] = g_texSrv[g_front][3];
    }
    g_ctx->PSSetShaderResources(0, 7, srvs);
    g_ctx->Draw(3, 0);

    restore_state(saved);
    g_internal = false;
    bbRtv->Release();
    bb->Release();
    if (mc) {
        if (!g_lastCompositeMs) log("compositor: drawing Minecraft into Palworld (%ux%u into %ux%u)", g_texW, g_texH, bd.Width, bd.Height);
        g_lastCompositeMs = now_ms();
    }
}

// Development: what near plane would make the depth at the screen centre agree with Lua's line trace?
static void calibrate_near(const LuaView& lua) {
    static ID3D11Texture2D* staging = nullptr;
    static UINT sw = 0, sh = 0;
    static DXGI_FORMAT sfmt = DXGI_FORMAT_UNKNOWN;
    float dist = lua.get<float>(PC_LUA_STATE_CENTER_DIST);
    if (!g_depthTex || dist < 0.3f) return;
    D3D11_TEXTURE2D_DESC d;
    g_depthTex->GetDesc(&d);
    if (!staging || sw != d.Width || sh != d.Height || sfmt != d.Format) {
        rel(staging);
        D3D11_TEXTURE2D_DESC s = d;
        s.Usage = D3D11_USAGE_STAGING;
        s.BindFlags = 0;
        s.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        s.MiscFlags = 0;
        if (FAILED(g_devc->CreateTexture2D(&s, nullptr, &staging))) return;
        sw = d.Width;
        sh = d.Height;
        sfmt = d.Format;
    }
    g_ctx->CopyResource(staging, g_depthTex);
    D3D11_MAPPED_SUBRESOURCE m;
    if (FAILED(g_ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) return;
    UINT x = (UINT)(g_depthVpW / 2), y = (UINT)(g_depthVpH / 2);
    const uint8_t* row = (const uint8_t*)m.pData + (size_t)y * m.RowPitch;
    float depth = 0;
    DXGI_FORMAT sf = depth_srv_format(d.Format);
    if (sf == DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS) depth = *(const float*)(row + x * 8);
    else if (sf == DXGI_FORMAT_R24_UNORM_X8_TYPELESS) depth = (float)(*(const uint32_t*)(row + x * 4) & 0xFFFFFF) / 16777215.0f;
    else if (sf == DXGI_FORMAT_R32_FLOAT) depth = *(const float*)(row + x * 4);
    g_ctx->Unmap(staging, 0);
    log("near: centre depth %.6f, traced %.2f m -> near %.4f m (in use %.4f)", depth, dist, depth * dist,
        lua.get<float>(PC_LUA_STATE_NEAR_Z));
}

// ---------------------------------------------------------------------------------------------------
// State for Minecraft, and the F8 hand-over

static void publish_state(const LuaView& lua, UINT bbW, UINT bbH) {
    uint8_t local[PC_SIZE_STATE];
    memset(local, 0, sizeof(local));
    uint32_t flags = 0;
    RECT rc;
    POINT tl = {0, 0};
    if (g_hwnd && GetClientRect(g_hwnd, &rc) && ClientToScreen(g_hwnd, &tl) && rc.right > rc.left) {
        int32_t win[4] = {tl.x, tl.y, rc.right - rc.left, rc.bottom - rc.top};
        memcpy(local + PC_GAME_STATE_WIN, win, sizeof(win));
        uint32_t bbs[2] = {bbW, bbH};
        memcpy(local + PC_GAME_STATE_BB, bbs, sizeof(bbs));
        flags |= PC_STATE_WINDOW_VALID;
        if (GetForegroundWindow() == g_hwnd) flags |= PC_STATE_WINDOW_FOCUSED;
    }
    if (now_ms() - g_lastCompositeMs < 500) flags |= PC_STATE_COMPOSITING;
    if (lua.fresh) {
        flags |= lua.get<uint32_t>(PC_LUA_STATE_FLAGS) &
                 (PC_STATE_CAMERA_VALID | PC_STATE_PLAYER_VALID | PC_STATE_CAM_OVERRIDDEN | PC_STATE_PLAYER_DEAD | PC_STATE_HOST_BUSY);
        memcpy(local + PC_GAME_STATE_CAM_POS, lua.raw + PC_LUA_STATE_CAM_POS, 36);  // pos, target, up
        memcpy(local + PC_GAME_STATE_FOV_YDEG, lua.raw + PC_LUA_STATE_FOV_YDEG, 12);  // fov, near, far
        memcpy(local + PC_GAME_STATE_PLAYER_POS, lua.raw + PC_LUA_STATE_PLAYER_POS, 28);  // pos, quat
        memcpy(local + PC_GAME_STATE_STAGE_ID, lua.raw + PC_LUA_STATE_STAGE_ID, 4);
    } else {
        flags |= PC_STATE_HOST_BUSY;  // title screen, loading: the Lua mod is not ticking
    }
    float aspect = bbH ? (float)bbW / (float)bbH : 1.777f, one = 1.0f;
    memcpy(local + PC_GAME_STATE_ASPECT, &aspect, 4);
    memcpy(local + PC_GAME_STATE_UNITS_PER_METER, &one, 4);
    memcpy(local + PC_GAME_STATE_FLAGS, &flags, 4);
    memcpy(local + PC_GAME_STATE_FRAME, &g_presents, 8);

    volatile uint32_t& seq = at<volatile uint32_t>(g_shm, PC_OFF_STATE);
    seq = seq + 1;
    _mm_mfence();
    memcpy(g_shm + PC_OFF_STATE + 4, local + 4, PC_SIZE_STATE - 4);
    _mm_mfence();
    seq = seq + 1;
    HDR(uint64_t, HOST_HEARTBEAT) = g_presents;
}

static void handle_switching() {
    static bool f8Down = false, seenInit = false;
    static uint32_t seen = 0;
    if (!g_hwnd) return;
    bool down = (GetAsyncKeyState(PC_VK_SWITCH_TO_MC) & 0x8000) != 0;
    uint32_t req = HDR(uint32_t, HOST_FOCUS_REQ);
    if (!seenInit) {
        seen = req;
        seenInit = true;
    }
    if (req != seen) {
        seen = req;
        f8Down = down;  // the press that handed over must not hand straight back
        ShowWindow(g_hwnd, SW_RESTORE);
        SetForegroundWindow(g_hwnd);
        log("switch: Minecraft handed control to Palworld (foreground %s)", GetForegroundWindow() == g_hwnd ? "ok" : "not yet");
        return;
    }
    if (GetForegroundWindow() == g_hwnd && down && !f8Down && mc_alive()) {
        HDR(uint32_t, MC_SWITCH_REQ) = HDR(uint32_t, MC_SWITCH_REQ) + 1;
        log("switch: F8 in Palworld -> back to Minecraft");
    }
    f8Down = down;
}

// ---------------------------------------------------------------------------------------------------
// Present

static bool adopt_swapchain(IDXGISwapChain* sc) {
    DXGI_SWAP_CHAIN_DESC d;
    if (FAILED(sc->GetDesc(&d)) || !d.OutputWindow || d.BufferDesc.Width < 320) return false;
    ID3D11Device* dev = nullptr;
    if (FAILED(sc->GetDevice(__uuidof(ID3D11Device), (void**)&dev))) return false;  // not D3D11 (e.g. -dx12)
    g_devc = dev;
    g_devc->GetImmediateContext(&g_ctx);
    g_sc = sc;
    g_hwnd = d.OutputWindow;
    log("present: Palworld swapchain %ux%u format %u, window %p, thread %lu", d.BufferDesc.Width, d.BufferDesc.Height,
        (unsigned)d.BufferDesc.Format, (void*)g_hwnd, GetCurrentThreadId());
    return true;
}

static void on_present(IDXGISwapChain* sc, UINT flags) {
    if (g_stopped || !g_shm || (flags & DXGI_PRESENT_TEST)) return;
    if (!g_sc && !adopt_swapchain(sc)) return;
    if (sc != g_sc) return;
    g_presents++;
    DXGI_SWAP_CHAIN_DESC d;
    sc->GetDesc(&d);
    UINT bbW = d.BufferDesc.Width, bbH = d.BufferDesc.Height;

    static uint32_t lastTick = 0;
    static uint64_t lastTickMs = 0;
    LuaView lua;
    memset(&lua, 0, sizeof(lua));
    bool got = seq_read(PC_OFF_LUASTATE, lua.raw, PC_SIZE_LUASTATE);
    uint32_t tick = lua.get<uint32_t>(PC_LUA_STATE_TICK_COUNT);
    uint64_t now = now_ms();
    if (got && tick != lastTick) {
        lastTick = tick;
        lastTickMs = now;
    }
    lua.fresh = got && lastTickMs && now - lastTickMs < 500;

    adopt_depth(bbW, bbH);
    if (!g_failed) composite(lua, bbW, bbH);
    if (g_dev && lua.fresh && g_presents % 300 == 0) {
        g_internal = true;
        calibrate_near(lua);
        g_internal = false;
    }
    cands_reset();
    publish_state(lua, bbW, bbH);
    handle_switching();
}

typedef HRESULT(STDMETHODCALLTYPE* Present_t)(IDXGISwapChain*, UINT, UINT);
typedef HRESULT(STDMETHODCALLTYPE* Present1_t)(IDXGISwapChain1*, UINT, UINT, const DXGI_PRESENT_PARAMETERS*);
typedef HRESULT(STDMETHODCALLTYPE* Resize_t)(IDXGISwapChain*, UINT, UINT, UINT, DXGI_FORMAT, UINT);
static Present_t oPresent = nullptr;
static Present1_t oPresent1 = nullptr;
static Resize_t oResize = nullptr;
static thread_local int t_inPresent = 0;

static HRESULT STDMETHODCALLTYPE hkPresent(IDXGISwapChain* sc, UINT sync, UINT flags) {
    if (!t_inPresent++) on_present(sc, flags);
    HRESULT hr = oPresent(sc, sync, flags);
    t_inPresent--;
    return hr;
}

static HRESULT STDMETHODCALLTYPE hkPresent1(IDXGISwapChain1* sc, UINT sync, UINT flags, const DXGI_PRESENT_PARAMETERS* pp) {
    if (!t_inPresent++) on_present(sc, flags);
    HRESULT hr = oPresent1(sc, sync, flags, pp);
    t_inPresent--;
    return hr;
}

static HRESULT STDMETHODCALLTYPE hkResize(IDXGISwapChain* sc, UINT n, UINT w, UINT h, DXGI_FORMAT f, UINT flags) {
    if (sc == g_sc) {
        release_scene();
        log("present: back buffers resize to %ux%u", w, h);
    }
    return oResize(sc, n, w, h, f, flags);
}

// ---------------------------------------------------------------------------------------------------
// Start-up

static bool hook(void* target, void* detour, void** original, const char* name) {
    MH_STATUS s = MH_CreateHook(target, detour, original);
    if (s != MH_OK) {
        log("hook: %s create failed (%s)", name, MH_StatusToString(s));
        return false;
    }
    return true;
}

static bool install_hooks() {
    // A throwaway device and swapchain: their method tables are the ones Palworld's use.
    WNDCLASSEXA wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(nullptr);
    wc.lpszClassName = "PalCraftProbe";
    RegisterClassExA(&wc);
    HWND w = CreateWindowExA(0, wc.lpszClassName, "", WS_OVERLAPPED, 0, 0, 64, 64, nullptr, nullptr, wc.hInstance, nullptr);
    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferCount = 1;
    sd.BufferDesc.Width = sd.BufferDesc.Height = 64;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = w;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    IDXGISwapChain* sc = nullptr;
    ID3D11Device* dev = nullptr;
    ID3D11DeviceContext* ctx = nullptr;
    D3D_FEATURE_LEVEL fl;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &sd,
                                               &sc, &dev, &fl, &ctx);
    if (FAILED(hr)) {
        log("hook: probe device failed (%08lx)", (unsigned long)hr);
        DestroyWindow(w);
        return false;
    }
    void** scv = *(void***)sc;
    void** cv = *(void***)ctx;
    IDXGISwapChain1* sc1 = nullptr;
    void** sc1v = SUCCEEDED(sc->QueryInterface(__uuidof(IDXGISwapChain1), (void**)&sc1)) ? *(void***)sc1 : nullptr;
    bool ok = MH_Initialize() == MH_OK;
    ok = ok && hook(scv[PC_SLOT_PRESENT], (void*)hkPresent, (void**)&oPresent, "Present");
    ok = ok && hook(scv[PC_SLOT_RESIZE], (void*)hkResize, (void**)&oResize, "ResizeBuffers");
    if (ok && sc1v) hook(sc1v[PC_SLOT_PRESENT1], (void*)hkPresent1, (void**)&oPresent1, "Present1");
    ok = ok && hook(cv[PC_SLOT_SET_TARGETS], (void*)hkSetTargets, (void**)&oSetTargets, "OMSetRenderTargets");
    ok = ok && hook(cv[PC_SLOT_CLEAR_DEPTH], (void*)hkClearDepth, (void**)&oClearDepth, "ClearDepthStencilView");
    ok = ok && hook(cv[PC_SLOT_DRAW_INDEXED], (void*)hkDrawII, (void**)&oDrawII, "DrawIndexedInstanced");
    ok = ok && hook(cv[PC_SLOT_VIEWPORTS], (void*)hkViewports, (void**)&oViewports, "RSSetViewports");
    rel(sc1);
    ctx->Release();
    dev->Release();
    sc->Release();
    DestroyWindow(w);
    UnregisterClassA(wc.lpszClassName, wc.hInstance);
    if (!ok) return false;
    MH_STATUS s = MH_EnableHook(MH_ALL_HOOKS);
    log("hook: enable %s", MH_StatusToString(s));
    return s == MH_OK;
}

// Development reloads: a newer copy of this DLL asks the running one to let go of its hooks first.
static DWORD WINAPI main_thread(LPVOID) {
    char stopName[64], goneName[64];
    snprintf(stopName, sizeof(stopName), "PalCraftStop_%lu", GetCurrentProcessId());
    snprintf(goneName, sizeof(goneName), "PalCraftGone_%lu", GetCurrentProcessId());
    HANDLE stop = CreateEventA(nullptr, TRUE, FALSE, stopName);
    bool older = GetLastError() == ERROR_ALREADY_EXISTS;
    HANDLE gone = CreateEventA(nullptr, TRUE, FALSE, goneName);
    if (older) {
        ResetEvent(gone);
        SetEvent(stop);
        DWORD r = WaitForSingleObject(gone, 5000);
        log("start: an older copy was running; it let go (%s)", r == WAIT_OBJECT_0 ? "ok" : "timeout");
        ResetEvent(stop);
    }
    log("start: PalCraft native, mod folder %s, runtime %s%s", g_modDir, g_runtime, g_dev ? " (development)" : "");
    if (!shm_open() || !install_hooks()) {
        log("start: FAILED; Minecraft will not be drawn");
        return 0;
    }
    WaitForSingleObject(stop, INFINITE);
    InterlockedExchange(&g_stopped, 1);
    MH_DisableHook(MH_ALL_HOOKS);
    Sleep(200);
    MH_Uninitialize();
    HDR(uint32_t, HOST_PID) = 0;
    log("stop: hooks removed for a newer copy");
    SetEvent(gone);
    return 0;
}

}  // namespace pc

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(self);
        // Lua frees its C libraries when its state closes (a mod reload). Our hooks must outlive that.
        HMODULE pinned;
        GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCSTR)&DllMain, &pinned);
        InitializeCriticalSection(&pc::g_logLock);
        pc::resolve_paths(self);
        HANDLE t = CreateThread(nullptr, 0, pc::main_thread, nullptr, 0, nullptr);
        if (t) CloseHandle(t);
    }
    return TRUE;
}

// Shaders.metal
// 全屏纹理渲染 shader，支持多种像素缩放滤镜

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vid [[vertex_id]],
                               constant float4* vertices [[buffer(0)]]) {
    VertexOut out;
    float4 v = vertices[vid];
    out.position = float4(v.x, v.y, 0.0, 1.0);
    out.texCoord = float2(v.z, v.w);
    return out;
}

// MARK: - 最近邻（原始像素风）
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    return tex.sample(samp, in.texCoord);
}

// MARK: - Sharp Bilinear：保留像素边缘的双线性插值
// 原理：在像素中心区域保持硬边缘，仅在像素边界做亚像素平滑
// 效果：比 nearest 清晰，比普通 linear 锐利，无模糊感
fragment float4 fragmentSharpBilinear(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       constant float2& texSize [[buffer(0)]]) {
    float2 uv = in.texCoord * texSize - 0.5;
    float2 iuv = floor(uv);
    float2 fuv = uv - iuv;

    // 在像素中心区域 sharpen，边缘区域 smooth
    float2 suv = clamp(fuv / fwidth(uv), 0.0, 0.5)
               + clamp((fuv - 1.0) / fwidth(uv) + 0.5, 0.0, 0.5);

    float2 coord = (iuv + suv + 0.5) / texSize;
    constexpr sampler linearSamp(filter::linear, address::clamp_to_edge);
    return tex.sample(linearSamp, coord);
}

// MARK: - LCD Grid：模拟复古 LCD 像素格子效果（GBA 专属感）
fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 sampler samp [[sampler(0)]],
                                 constant float2& texSize [[buffer(0)]]) {
    constexpr sampler linearSamp(filter::linear, address::clamp_to_edge);
    float4 color = tex.sample(linearSamp, in.texCoord);

    // 计算当前像素在原始纹理中的子像素位置
    float2 pixelPos = fract(in.texCoord * texSize);

    // 水平 RGB 子像素条纹
    float3 mask;
    float px = pixelPos.x * 3.0;
    if (px < 1.0)      mask = float3(1.0, 0.3, 0.3);
    else if (px < 2.0) mask = float3(0.3, 1.0, 0.3);
    else               mask = float3(0.3, 0.3, 1.0);

    // 垂直扫描线暗化
    float scanline = 1.0 - 0.15 * step(0.75, pixelPos.y);

    color.rgb *= mask * scanline;
    return color;
}

// MARK: - CRT：桶形畸变 + 扫描线 + 边缘暗角
fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler samp [[sampler(0)]],
                             constant float2& texSize [[buffer(0)]]) {
    constexpr sampler linearSamp(filter::linear, address::clamp_to_edge);

    // 桶形畸变
    float2 uv = in.texCoord * 2.0 - 1.0;
    float2 offset = uv.yx * uv.yx * uv * 0.07;
    uv = uv + offset;
    float2 distorted = uv * 0.5 + 0.5;

    // 超出边界时显示黑色
    if (distorted.x < 0.0 || distorted.x > 1.0 ||
        distorted.y < 0.0 || distorted.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float4 color = tex.sample(linearSamp, distorted);

    // 扫描线：每隔一行暗化
    float scanline = 1.0 - 0.25 * step(0.5, fract(distorted.y * texSize.y));
    color.rgb *= scanline;

    // 边缘暗角（vignette）
    float2 vig = uv * uv;
    float vignette = 1.0 - dot(vig, float2(0.35, 0.35));
    color.rgb *= clamp(vignette, 0.0, 1.0);

    // 轻微 RGB 色散（chromatic aberration）
    float aberration = 0.002;
    float r = tex.sample(linearSamp, distorted + float2(aberration, 0.0)).r;
    float b = tex.sample(linearSamp, distorted - float2(aberration, 0.0)).b;
    color.r = r * scanline * clamp(vignette, 0.0, 1.0);
    color.b = b * scanline * clamp(vignette, 0.0, 1.0);

    return color;
}

// MARK: - Scanline：轻量扫描线，不做畸变
fragment float4 fragmentScanline(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler samp [[sampler(0)]],
                                  constant float2& texSize [[buffer(0)]]) {
    constexpr sampler linearSamp(filter::linear, address::clamp_to_edge);
    float4 color = tex.sample(linearSamp, in.texCoord);

    // 每隔一行暗化 30%
    float line = fract(in.texCoord.y * texSize.y);
    float scanline = 1.0 - 0.30 * step(0.5, line);
    color.rgb *= scanline;

    return color;
}

// MARK: - NTSC：模拟 NTSC 色彩串扰（亮度/色度分离 + 横向模糊）
fragment float4 fragmentNTSC(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler samp [[sampler(0)]],
                              constant float2& texSize [[buffer(0)]]) {
    constexpr sampler linearSamp(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;
    float dx = 1.0 / texSize.x;

    // 横向 3-tap 模糊模拟色度串扰
    float4 c0 = tex.sample(linearSamp, uv + float2(-dx, 0.0));
    float4 c1 = tex.sample(linearSamp, uv);
    float4 c2 = tex.sample(linearSamp, uv + float2( dx, 0.0));

    // 亮度保持清晰，色度横向模糊
    float3 luma   = float3(0.299, 0.587, 0.114);
    float y  = dot(c1.rgb, luma);
    float3 chroma = (c0.rgb * 0.25 + c1.rgb * 0.5 + c2.rgb * 0.25);

    // 重建：亮度 + 模糊色度
    float3 result = float3(y) + (chroma - float3(dot(chroma, luma)));

    // 轻微饱和度提升（NTSC 色彩偏暖）
    float3 gray = float3(dot(result, luma));
    result = mix(gray, result, 1.3);

    // 扫描线
    float scanline = 1.0 - 0.18 * step(0.5, fract(uv.y * texSize.y));
    result *= scanline;

    return float4(clamp(result, 0.0, 1.0), 1.0);
}

// MARK: - xBR HD：像素艺术边缘检测放大（高清重制风格）
// 原理：对每个像素采样 3×3 邻域，通过颜色差异检测对角线边缘，
//       用加权混合代替硬边缘，将斜线/曲线变平滑，直线保持锐利。
// 效果：接近 HQ2x/xBR 高清重制，消除锯齿感，保留像素艺术风格。

// 颜色距离（感知加权）
static float colorDist(float3 a, float3 b) {
    float3 d = a - b;
    // 人眼对绿色最敏感，加权 YUV 近似
    return dot(d * d, float3(0.299, 0.587, 0.114));
}

fragment float4 fragmentXBR(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler samp [[sampler(0)]],
                             constant float2& texSize [[buffer(0)]]) {
    constexpr sampler nearSamp(filter::nearest, address::clamp_to_edge);
    constexpr sampler linSamp(filter::linear,  address::clamp_to_edge);

    float2 uv    = in.texCoord;
    float2 pixel = 1.0 / texSize;

    // 采样 3×3 邻域（中心 + 8 邻居）
    float3 C  = tex.sample(nearSamp, uv).rgb;
    float3 N  = tex.sample(nearSamp, uv + float2( 0, -pixel.y)).rgb;
    float3 S  = tex.sample(nearSamp, uv + float2( 0,  pixel.y)).rgb;
    float3 W  = tex.sample(nearSamp, uv + float2(-pixel.x,  0)).rgb;
    float3 E  = tex.sample(nearSamp, uv + float2( pixel.x,  0)).rgb;
    float3 NW = tex.sample(nearSamp, uv + float2(-pixel.x, -pixel.y)).rgb;
    float3 NE = tex.sample(nearSamp, uv + float2( pixel.x, -pixel.y)).rgb;
    float3 SW = tex.sample(nearSamp, uv + float2(-pixel.x,  pixel.y)).rgb;
    float3 SE = tex.sample(nearSamp, uv + float2( pixel.x,  pixel.y)).rgb;

    // 亚像素位置（0~1 内的小数部分，表示在当前像素格内的位置）
    float2 subpix = fract(uv * texSize);

    // 四条对角线的边缘强度
    // 主对角线 NW-SE：若 NW≈C 且 SE≈C，说明是对角边缘
    float diagNWSE = colorDist(NW, SE);
    float diagNESW = colorDist(NE, SW);
    float horizEdge = colorDist(N, S);
    float vertEdge  = colorDist(W, E);

    // 边缘方向权重
    float edgeH = horizEdge / (horizEdge + vertEdge + 1e-5);
    float edgeV = 1.0 - edgeH;

    // 对角线平滑：检测 NW-SE 和 NE-SW 方向
    // 若某对角线两端颜色接近中心，说明中心在该对角线上，做平滑
    float wNWSE = 1.0 / (diagNWSE + 1e-3);
    float wNESW = 1.0 / (diagNESW + 1e-3);
    float wTotal = wNWSE + wNESW;
    wNWSE /= wTotal;
    wNESW /= wTotal;

    // 根据亚像素位置决定混合方向
    // 左上/右下象限 → NW-SE 对角线平滑
    // 右上/左下象限 → NE-SW 对角线平滑
    float diagBlend;
    float3 diagColor;
    if (subpix.x + subpix.y < 1.0) {
        // 左上象限：偏向 NW
        diagColor = mix(C, NW, wNWSE * 0.5);
        diagBlend = wNWSE;
    } else {
        // 右下象限：偏向 SE
        diagColor = mix(C, SE, wNWSE * 0.5);
        diagBlend = wNWSE;
    }
    if (subpix.x > subpix.y) {
        // 右上象限：偏向 NE
        diagColor = mix(diagColor, NE, wNESW * 0.4);
    } else {
        // 左下象限：偏向 SW
        diagColor = mix(diagColor, SW, wNESW * 0.4);
    }

    // 水平/垂直边缘平滑（用 linear 采样做亚像素插值）
    float3 linearColor = tex.sample(linSamp, uv).rgb;

    // 边缘强度：越强越用对角混合，越弱越接近 linear
    float edgeStrength = clamp((diagNWSE + diagNESW) * 8.0, 0.0, 1.0);

    // 最终混合：对角平滑 + linear 插值 + 轻微锐化
    float3 blended = mix(linearColor, diagColor, edgeStrength * 0.65);

    // 轻微 unsharp mask 锐化，找回细节
    float3 blur = (N + S + W + E) * 0.25;
    blended = blended + (blended - blur) * 0.3;

    return float4(clamp(blended, 0.0, 1.0), 1.0);
}

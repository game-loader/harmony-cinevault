// Queries the system decoder list (hardware and software) through AVCodec capability APIs and
// returns it to ArkTS as a JSON string. Used to build the Emby/Jellyfin DeviceProfile and the
// "解码能力" page. Pure read-only query, no decoder instances are created.
#include <napi/native_api.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <string>
#include <vector>

namespace {

struct Mime {
    const char *key;   // short name used by ArkTS
    const char *mime;  // may be null on older systems (weak symbol not resolved)
    bool video;
};

void AppendEscaped(std::string &out, const char *s) {
    out += '"';
    for (const char *p = s ? s : ""; *p; ++p) {
        if (*p == '"' || *p == '\\') {
            out += '\\';
            out += *p;
        } else if (static_cast<unsigned char>(*p) < 0x20) {
            out += ' ';
        } else {
            out += *p;
        }
    }
    out += '"';
}

void AppendCap(std::string &out, OH_AVCapability *cap, bool video) {
    out += "{\"name\":";
    AppendEscaped(out, OH_AVCapability_GetName(cap));
    out += ",\"hw\":";
    out += OH_AVCapability_IsHardware(cap) ? "true" : "false";
    out += ",\"instances\":" + std::to_string(OH_AVCapability_GetMaxSupportedInstances(cap));
    if (video) {
        OH_AVRange w = {0, 0};
        OH_AVRange h = {0, 0};
        OH_AVCapability_GetVideoWidthRange(cap, &w);
        OH_AVCapability_GetVideoHeightRange(cap, &h);
        out += ",\"maxWidth\":" + std::to_string(w.maxVal);
        out += ",\"maxHeight\":" + std::to_string(h.maxVal);
        out += ",\"uhd60\":";
        out += OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap, 3840, 2160, 60) ? "true" : "false";
        out += ",\"uhd30\":";
        out += OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap, 3840, 2160, 30) ? "true" : "false";
        out += ",\"fhd60\":";
        out += OH_AVCapability_AreVideoSizeAndFrameRateSupported(cap, 1920, 1080, 60) ? "true" : "false";
    } else {
        OH_AVRange ch = {0, 0};
        OH_AVCapability_GetAudioChannelCountRange(cap, &ch);
        out += ",\"maxChannels\":" + std::to_string(ch.maxVal);
    }
    const int32_t *profiles = nullptr;
    uint32_t n = 0;
    out += ",\"profiles\":[";
    if (OH_AVCapability_GetSupportedProfiles(cap, &profiles, &n) == AV_ERR_OK && profiles != nullptr) {
        for (uint32_t i = 0; i < n; ++i) {
            if (i > 0) {
                out += ',';
            }
            out += std::to_string(profiles[i]);
        }
    }
    out += "]}";
}

std::string Probe() {
    const std::vector<Mime> mimes = {
        {"h264", OH_AVCODEC_MIMETYPE_VIDEO_AVC, true},
        {"hevc", OH_AVCODEC_MIMETYPE_VIDEO_HEVC, true},
        {"vvc", OH_AVCODEC_MIMETYPE_VIDEO_VVC, true},
        {"av1", OH_AVCODEC_MIMETYPE_VIDEO_AV1, true},
        {"vp9", OH_AVCODEC_MIMETYPE_VIDEO_VP9, true},
        {"vp8", OH_AVCODEC_MIMETYPE_VIDEO_VP8, true},
        {"mpeg2video", OH_AVCODEC_MIMETYPE_VIDEO_MPEG2, true},
        {"mpeg4", OH_AVCODEC_MIMETYPE_VIDEO_MPEG4_PART2, true},
        {"h263", OH_AVCODEC_MIMETYPE_VIDEO_H263, true},
        {"vc1", OH_AVCODEC_MIMETYPE_VIDEO_WVC1, true},
        {"wmv3", OH_AVCODEC_MIMETYPE_VIDEO_WMV3, true},
        {"rv40", OH_AVCODEC_MIMETYPE_VIDEO_RV40, true},
        {"mjpeg", OH_AVCODEC_MIMETYPE_VIDEO_MJPEG, true},
        {"aac", OH_AVCODEC_MIMETYPE_AUDIO_AAC, false},
        {"mp3", OH_AVCODEC_MIMETYPE_AUDIO_MPEG, false},
        {"flac", OH_AVCODEC_MIMETYPE_AUDIO_FLAC, false},
        {"vorbis", OH_AVCODEC_MIMETYPE_AUDIO_VORBIS, false},
        {"opus", OH_AVCODEC_MIMETYPE_AUDIO_OPUS, false},
        {"alac", OH_AVCODEC_MIMETYPE_AUDIO_ALAC, false},
        {"ape", OH_AVCODEC_MIMETYPE_AUDIO_APE, false},
        {"ac3", OH_AVCODEC_MIMETYPE_AUDIO_AC3, false},
        {"eac3", OH_AVCODEC_MIMETYPE_AUDIO_EAC3, false},
        {"dts", OH_AVCODEC_MIMETYPE_AUDIO_DTS, false},
        {"truehd", OH_AVCODEC_MIMETYPE_AUDIO_TRUEHD, false},
        {"wma", OH_AVCODEC_MIMETYPE_AUDIO_WMAPRO, false},
        {"pcm", OH_AVCODEC_MIMETYPE_AUDIO_RAW, false},
    };
    std::string out = "[";
    bool first = true;
    for (const Mime &m : mimes) {
        if (!first) {
            out += ',';
        }
        first = false;
        out += "{\"codec\":";
        AppendEscaped(out, m.key);
        out += ",\"video\":";
        out += m.video ? "true" : "false";
        out += ",\"mime\":";
        AppendEscaped(out, m.mime);
        out += ",\"decoders\":[";
        bool any = false;
        if (m.mime != nullptr) {
            OH_AVCapability *hw = OH_AVCodec_GetCapabilityByCategory(m.mime, false, HARDWARE);
            if (hw != nullptr && OH_AVCapability_IsHardware(hw)) {
                AppendCap(out, hw, m.video);
                any = true;
            }
            OH_AVCapability *sw = OH_AVCodec_GetCapabilityByCategory(m.mime, false, SOFTWARE);
            if (sw != nullptr && !OH_AVCapability_IsHardware(sw)) {
                if (any) {
                    out += ',';
                }
                AppendCap(out, sw, m.video);
            }
        }
        out += "]}";
    }
    out += "]";
    return out;
}

napi_value ProbeNapi(napi_env env, napi_callback_info info) {
    std::string json = Probe();
    napi_value result = nullptr;
    napi_create_string_utf8(env, json.c_str(), json.size(), &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"probe", nullptr, ProbeNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "codecprobe",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterCodecProbe(void) {
    napi_module_register(&g_module);
}

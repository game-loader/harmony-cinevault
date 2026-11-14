import { nativeProbeJson } from './NativeProbe';

/** One decoder implementation reported by the system (see cpp/codec_probe.cpp). */
export class DecoderInfo {
  name: string = '';
  hw: boolean = false;
  instances: number = 0;
  maxWidth: number = 0;     // video only
  maxHeight: number = 0;    // video only
  uhd60: boolean = false;
  uhd30: boolean = false;
  fhd60: boolean = false;
  maxChannels: number = 0;  // audio only
  profiles: number[] = [];
}

/** Probe result for one codec. codec uses Emby/ffmpeg names: h264 hevc vvc av1 vp9 vp8 mpeg2video mpeg4 h263 vc1 wmv3 rv40 mjpeg aac mp3 flac vorbis opus alac ape ac3 eac3 dts truehd wma pcm */
export class CodecEntry {
  codec: string = '';
  video: boolean = false;
  mime: string = '';
  decoders: DecoderInfo[] = [];
}

/**
 * OWNER: codec agent. Facade over the native probe. load() is synchronous and cached; call it once at startup
 * (EntryAbility) and whenever entries are needed. Signatures below are the contract other modules use.
 */
export class CodecCaps {
  static load(): CodecEntry[] { return []; }
  static entries(): CodecEntry[] { return []; }
  static has(codec: string): boolean { return false; }
  static isHardware(codec: string): boolean { return false; }
  /** Largest height any decoder for this codec supports (0 = none) */
  static maxHeight(codec: string): number { return 0; }
  /** Decoder that would be used for this codec (hardware preferred), undefined if none */
  static decoderFor(codec: string): DecoderInfo | undefined { return undefined; }
  /** Plain-text report for the "复制报告" button */
  static report(): string { return ''; }
}

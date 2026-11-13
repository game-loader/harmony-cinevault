// Emby/Jellyfin DeviceProfile describing what HarmonyOS AVPlayer can play. Pure module (no imports).
// Codec list follows media.CodecMimeType in API 26 (avc, hevc, aac, mp3, flac, vorbis). Opus/AC3/EAC3/DTS,
// VP9 and AV1 are deliberately left out so the server remuxes/transcodes audio to AAC instead of failing.

export class DirectPlayProfile {
  Container: string = '';
  Type: string = 'Video';
  VideoCodec?: string;
  AudioCodec?: string;
}

export class TranscodingProfile {
  Container: string = 'ts';
  Type: string = 'Video';
  VideoCodec: string = 'h264';
  AudioCodec: string = 'aac';
  Protocol: string = 'hls';
  Context: string = 'Streaming';
  MaxAudioChannels: string = '6';
  MinSegments: number = 1;
  BreakOnNonKeyFrames: boolean = true;
  CopyTimestamps: boolean = false;
}

export class SubtitleProfile {
  Format: string = '';
  Method: string = 'External';
}

export class ProfileCondition {
  Condition: string = 'LessThanEqual';
  Property: string = '';
  Value: string = '';
  IsRequired: boolean = false;
}

export class CodecProfile {
  Type: string = 'Video';
  Codec: string = '';
  Conditions: ProfileCondition[] = [];
}

export class ResponseProfile {
  Type: string = 'Video';
  Container: string = '';
  MimeType: string = '';
}

export class DeviceProfile {
  Name: string = 'CineVault HarmonyOS';
  MaxStreamingBitrate: number = 200000000;
  MaxStaticBitrate: number = 200000000;
  MusicStreamingTranscodingBitrate: number = 320000;
  DirectPlayProfiles: DirectPlayProfile[] = [];
  TranscodingProfiles: TranscodingProfile[] = [];
  SubtitleProfiles: SubtitleProfile[] = [];
  CodecProfiles: CodecProfile[] = [];
  ResponseProfiles: ResponseProfile[] = [];
  ContainerProfiles: CodecProfile[] = [];
}

export const DEFAULT_MAX_BITRATE: number = 200000000;
export const VIDEO_CODECS: string = 'h264,hevc,h265';
export const AUDIO_CODECS: string = 'aac,mp3,flac,vorbis';
export const DIRECT_CONTAINERS: string[] = ['mp4', 'm4v', 'mkv', 'mov', 'ts', 'm2ts', 'mpegts', 'flv', 'webm', 'hls'];

function directVideo(container: string): DirectPlayProfile {
  const p = new DirectPlayProfile();
  p.Container = container;
  p.Type = 'Video';
  p.VideoCodec = VIDEO_CODECS;
  p.AudioCodec = AUDIO_CODECS;
  return p;
}

function sub(format: string, method: string): SubtitleProfile {
  const s = new SubtitleProfile();
  s.Format = format;
  s.Method = method;
  return s;
}

function cond(condition: string, property: string, value: string, required: boolean): ProfileCondition {
  const c = new ProfileCondition();
  c.Condition = condition;
  c.Property = property;
  c.Value = value;
  c.IsRequired = required;
  return c;
}

/** maxBitrate in bits per second; 0 or negative = default 200 Mbps. */
export function buildDeviceProfile(maxBitrate: number): DeviceProfile {
  const bitrate = maxBitrate > 0 ? Math.floor(maxBitrate) : DEFAULT_MAX_BITRATE;
  const p = new DeviceProfile();
  p.MaxStreamingBitrate = bitrate;
  p.MaxStaticBitrate = bitrate;

  DIRECT_CONTAINERS.forEach((c: string) => {
    p.DirectPlayProfiles.push(directVideo(c));
  });
  const audioOnly = new DirectPlayProfile();
  audioOnly.Container = 'mp3,aac,m4a,flac,ogg';
  audioOnly.Type = 'Audio';
  p.DirectPlayProfiles.push(audioOnly);

  const hls = new TranscodingProfile();
  p.TranscodingProfiles.push(hls);
  const audioT = new TranscodingProfile();
  audioT.Type = 'Audio';
  audioT.Container = 'aac';
  audioT.VideoCodec = '';
  audioT.Protocol = 'http';
  audioT.MaxAudioChannels = '2';
  p.TranscodingProfiles.push(audioT);

  // Text subtitles are fetched as external files by the player; image subtitles are burned in on transcode.
  ['srt', 'subrip', 'vtt', 'webvtt', 'ass', 'ssa'].forEach((f: string) => {
    p.SubtitleProfiles.push(sub(f, 'External'));
  });
  ['pgssub', 'pgs', 'dvdsub', 'dvbsub', 'vobsub'].forEach((f: string) => {
    p.SubtitleProfiles.push(sub(f, 'Encode'));
  });

  const h264 = new CodecProfile();
  h264.Codec = 'h264';
  h264.Conditions.push(cond('NotEquals', 'IsAnamorphic', 'true', false));
  h264.Conditions.push(cond('LessThanEqual', 'VideoBitDepth', '8', false));
  h264.Conditions.push(cond('LessThanEqual', 'VideoLevel', '52', false));
  p.CodecProfiles.push(h264);
  const hevc = new CodecProfile();
  hevc.Codec = 'hevc,h265';
  hevc.Conditions.push(cond('LessThanEqual', 'VideoBitDepth', '10', false));
  p.CodecProfiles.push(hevc);
  const audio = new CodecProfile();
  audio.Type = 'VideoAudio';
  audio.Codec = 'aac,mp3,flac,vorbis';
  audio.Conditions.push(cond('LessThanEqual', 'AudioChannels', '8', false));
  p.CodecProfiles.push(audio);

  return p;
}

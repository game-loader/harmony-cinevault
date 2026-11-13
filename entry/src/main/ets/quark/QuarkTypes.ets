// JSON shapes of the Quark drive API (fields we use only).

export class QuarkConst {
  static readonly API_PC: string = 'https://drive-pc.quark.cn/1/clouddrive';
  static readonly API_ALT: string = 'https://drive.quark.cn/1/clouddrive';
  static readonly REFERER: string = 'https://pan.quark.cn';
  static readonly ORIGIN: string = 'https://pan.quark.cn';
  static readonly ACCOUNT_INFO: string = 'https://pan.quark.cn/account/info?fr=pc&platform=pc';
  static readonly UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.4 Safari/537.36 Channel/pckk_other_ch';
  /** Desktop browser UA for the login web view (so pan.quark.cn shows the QR login). */
  static readonly WEB_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'Chrome/124.0.0.0 Safari/537.36';
  static readonly PAGE_SIZE: number = 100;
  /** __puus lives ~3h; refresh well before that. */
  static readonly PUUS_REFRESH_MS: number = 100 * 60 * 1000;
}

export interface QuarkEnvelope {
  status?: number;
  code?: number;
  message?: string;
}

export interface QuarkFileJson {
  fid?: string;
  file_name?: string;
  pdir_fid?: string;
  category?: number;
  file_type?: number;
  size?: number;
  format_type?: string;
  file?: boolean;
  dir?: boolean;
  created_at?: number;
  updated_at?: number;
  l_created_at?: number;
  l_updated_at?: number;
  thumbnail?: string;
  big_thumbnail?: string;
  include_items?: number;
  duration?: number;
}

export interface QuarkSortData {
  list?: QuarkFileJson[];
}

export interface QuarkSortMeta {
  _total?: number;
  _count?: number;
  _page?: number;
  _size?: number;
}

export interface QuarkSortResp extends QuarkEnvelope {
  data?: QuarkSortData;
  metadata?: QuarkSortMeta;
}

export interface QuarkDownloadItem {
  fid?: string;
  file_name?: string;
  download_url?: string;
  size?: number;
}

export interface QuarkDownloadResp extends QuarkEnvelope {
  data?: QuarkDownloadItem[];
}

export interface QuarkVideoInfo {
  url?: string;
  resolution?: string;
  width?: number;
  height?: number;
  duration?: number;
  size?: number;
  format?: string;
  bitrate?: number;
  codec?: string;
  hls_type?: string;
  success?: boolean;
}

export interface QuarkVideoEntry {
  resolution?: string;
  video_info?: QuarkVideoInfo;
}

export interface QuarkPlayData {
  default_resolution?: string;
  video_list?: QuarkVideoEntry[];
  file_name?: string;
  size?: number;
}

export interface QuarkPlayResp extends QuarkEnvelope {
  data?: QuarkPlayData;
}

export interface QuarkAccountData {
  nickname?: string;
  avatarUri?: string;
  mobilekps?: string;
}

export interface QuarkAccountResp {
  success?: boolean;
  code?: string | number;
  msg?: string;
  data?: QuarkAccountData;
}

export class QuarkPlayBody {
  fid: string = '';
  resolutions: string = 'normal,low,high,super,2k,4k';
  supports: string = 'fmp4,m3u8';
}

export class QuarkDownloadBody {
  fids: string[] = [];
}

/** Normalised drive entry used by the browser and the provider. */
export class QuarkFile {
  fid: string = '';
  name: string = '';
  parentFid: string = '';
  isDir: boolean = false;
  category: number = 0;      // 1 = video
  size: number = 0;
  updatedAt: number = 0;     // epoch ms
  formatType: string = '';
  thumbnail: string = '';
  duration: number = 0;      // seconds, if provided
}

export class QuarkQuality {
  resolution: string = '';
  label: string = '';
  url: string = '';
  width: number = 0;
  height: number = 0;
  durationSec: number = 0;
}

export class QuarkLink {
  url: string = '';
  /** Cookie snapshot the url was signed against: send it back unchanged */
  headers: Record<string, string> = {};
}

export class QuarkError extends Error {
  status: number;
  code: number;
  constructor(status: number, code: number, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function resolutionLabel(r: string): string {
  switch (r) {
    case '4k': return '4K';
    case '2k': return '2K';
    case 'super': return '超清 1080P';
    case 'high': return '高清 720P';
    case 'normal': return '标清 540P';
    case 'low': return '流畅 360P';
    default: return r;
  }
}

export function resolutionRank(r: string): number {
  const order: string[] = ['4k', '2k', 'super', 'high', 'normal', 'low'];
  const i = order.indexOf(r);
  return i < 0 ? order.length : i;
}

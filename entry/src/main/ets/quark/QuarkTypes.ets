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

// ---------------- TV client (open-api-drive.quark.cn) ----------------

/** Error / common envelope of the TV api: {status, errno, error_info, req_id}. */
export interface QuarkTvEnvelope {
  status?: number;
  errno?: number;
  error_info?: string;
  req_id?: string;
}

export interface QuarkTvAuthResp extends QuarkTvEnvelope {
  qr_data?: string;
  query_token?: string;
}

export interface QuarkTvCodeResp extends QuarkTvEnvelope {
  code?: string;
}

export interface QuarkTvTokenData {
  status?: number;
  errno?: number;
  error_info?: string;
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
}

export interface QuarkTvTokenResp {
  code?: number;
  message?: string;
  data?: QuarkTvTokenData;
}

export interface QuarkTvFileJson {
  fid?: string;
  parent_fid?: string;
  category?: number;
  filename?: string;
  size?: number;
  file_type?: string | number;
  isdir?: number;
  duration?: number;
  created_at?: number;
  updated_at?: number;
  thumbnail_url?: string;
}

export interface QuarkTvListData {
  total_count?: number;
  files?: QuarkTvFileJson[];
}

export interface QuarkTvListResp extends QuarkTvEnvelope {
  data?: QuarkTvListData;
}

export interface QuarkTvDownloadData {
  fid?: string;
  file_name?: string;
  size?: number;
  download_url?: string;
}

export interface QuarkTvDownloadResp extends QuarkTvEnvelope {
  data?: QuarkTvDownloadData;
}

export interface QuarkTvVideoInfo {
  resolution?: string;
  accessable?: number;
  trans_status?: string;
  duration?: number;
  size?: number;
  format?: string;
  width?: number;
  height?: number;
  url?: string;
  bitrate?: number;
}

export interface QuarkTvStreamData {
  default_resolution?: string;
  video_info?: QuarkTvVideoInfo[];
}

export interface QuarkTvStreamResp extends QuarkTvEnvelope {
  data?: QuarkTvStreamData;
}

/** Shape of /user?method=user_info is undocumented: read the usual name fields defensively. */
export interface QuarkTvUserData {
  nickname?: string;
  nick_name?: string;
  user_name?: string;
  name?: string;
}

export interface QuarkTvUserResp extends QuarkTvEnvelope {
  data?: QuarkTvUserData;
}

/** QR login challenge: image as data URI plus the token to poll with. */
export class QuarkTvQr {
  image: string = '';
  queryToken: string = '';
}

/**
 * Drive backend used by QuarkProvider / QuarkBrowser. Implemented by QuarkApi (web cookie) and QuarkTvApi (TV client).
 */
export interface QuarkDrive {
  /** 'cookie' | 'tv' */
  authMode(): string;
  /** All entries of a folder (follows paging). */
  listAll(fid: string): Promise<QuarkFile[]>;
  /** Original-quality link plus the headers the player must send. */
  downloadLink(fid: string): Promise<QuarkLink>;
  /** Server transcodes, best first; empty when none. */
  playQualities(fid: string): Promise<QuarkQuality[]>;
  /** Headers for transcode / subtitle urls. */
  streamHeaders(): Record<string, string>;
  /** Account display name; throws when not logged in. */
  accountName(): Promise<string>;
  /** Refresh credentials if due. Never throws. */
  ensureFresh(): Promise<void>;
}

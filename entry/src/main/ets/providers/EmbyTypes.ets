// Raw JSON shapes returned by Emby / Jellyfin REST APIs (subset we use). Pure: no imports.
// Every field is optional because the two servers (and versions) omit fields freely.

export interface EmbyUserData {
  Played?: boolean;
  IsFavorite?: boolean;
  PlaybackPositionTicks?: number;
  PlayCount?: number;
  LastPlayedDate?: string;
  UnplayedItemCount?: number;
}

export interface EmbyPerson {
  Name?: string;
  Id?: string;
  Role?: string;
  Type?: string;
  PrimaryImageTag?: string;
}

export interface EmbyNameId {
  Name?: string;
  Id?: string;
}

export interface EmbyMediaStream {
  Index?: number;
  Type?: string;            // Video | Audio | Subtitle | EmbeddedImage
  Codec?: string;
  Language?: string;
  Title?: string;
  DisplayTitle?: string;
  IsDefault?: boolean;
  IsForced?: boolean;
  IsExternal?: boolean;
  IsTextSubtitleStream?: boolean;
  SupportsExternalStream?: boolean;
  DeliveryMethod?: string;  // Embed | External | Hls | Encode
  DeliveryUrl?: string;
  Path?: string;
  Channels?: number;
  Width?: number;
  Height?: number;
  BitRate?: number;
  BitDepth?: number;
  Profile?: string;
  VideoRange?: string;          // Emby/Jellyfin: SDR | HDR
  VideoRangeType?: string;      // Jellyfin 10.9+: SDR | HDR10 | HDR10Plus | HLG | DOVI | DOVIWithHDR10 ...
  ColorTransfer?: string;       // smpte2084 | arib-std-b67 | bt709
  ExtendedVideoType?: string;   // Emby 4.8: None | Hdr10 | Hdr10Plus | HyperLogGamma | DolbyVision
}

export interface EmbyMediaSource {
  Id?: string;
  Name?: string;
  Path?: string;
  Protocol?: string;
  Container?: string;
  Size?: number;
  Bitrate?: number;
  RunTimeTicks?: number;
  IsRemote?: boolean;
  SupportsDirectPlay?: boolean;
  SupportsDirectStream?: boolean;
  SupportsTranscoding?: boolean;
  TranscodingUrl?: string;
  TranscodingSubProtocol?: string;
  TranscodingContainer?: string;
  TranscodeReasons?: string[];
  DirectStreamUrl?: string;
  DefaultAudioStreamIndex?: number;
  DefaultSubtitleStreamIndex?: number;
  MediaStreams?: EmbyMediaStream[];
  RequiredHttpHeaders?: Record<string, string>;
}

export interface EmbyItem {
  Id?: string;
  Name?: string;
  OriginalTitle?: string;
  SortName?: string;
  Type?: string;
  MediaType?: string;
  CollectionType?: string;
  IsFolder?: boolean;
  Overview?: string;
  ProductionYear?: number;
  PremiereDate?: string;
  CommunityRating?: number;
  OfficialRating?: string;
  RunTimeTicks?: number;
  Genres?: string[];
  Tags?: string[];
  Studios?: EmbyNameId[];
  People?: EmbyPerson[];
  ProviderIds?: Record<string, string>;
  ImageTags?: Record<string, string>;
  BackdropImageTags?: string[];
  ParentBackdropItemId?: string;
  ParentBackdropImageTags?: string[];
  ParentThumbItemId?: string;
  ParentThumbImageTag?: string;
  ParentLogoItemId?: string;
  ParentLogoImageTag?: string;
  ParentPrimaryImageItemId?: string;
  ParentPrimaryImageTag?: string;
  SeriesId?: string;
  SeriesName?: string;
  SeriesPrimaryImageTag?: string;
  SeasonId?: string;
  SeasonName?: string;
  ParentId?: string;
  ParentIndexNumber?: number;
  IndexNumber?: number;
  ChildCount?: number;
  RecursiveItemCount?: number;
  Container?: string;
  Width?: number;
  Height?: number;
  UserData?: EmbyUserData;
  MediaSources?: EmbyMediaSource[];
  MediaStreams?: EmbyMediaStream[];
}

export interface EmbyItemsResult {
  Items?: EmbyItem[];
  TotalRecordCount?: number;
  StartIndex?: number;
}

export interface EmbyAuthUser {
  Id?: string;
  Name?: string;
  ServerId?: string;
}

export interface EmbyAuthResult {
  User?: EmbyAuthUser;
  AccessToken?: string;
  ServerId?: string;
}

export interface EmbyPublicInfo {
  ServerName?: string;
  ProductName?: string;
  Version?: string;
  Id?: string;
  LocalAddress?: string;
}

export interface EmbyPlaybackInfoResult {
  MediaSources?: EmbyMediaSource[];
  PlaySessionId?: string;
  ErrorCode?: string;
}

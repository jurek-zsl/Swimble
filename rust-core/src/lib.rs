uniffi::setup_scaffolding!();

pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/mumble_proto.rs"));
}

pub mod audio_mixer;
pub mod cert;
pub mod client;
pub mod connection;
pub mod crypt_ocb2;
pub mod framing;
pub mod ping;
pub mod state;
pub mod voice_packet;

pub use cert::{
    export_identity_to_pkcs12, generate_client_identity, import_identity_from_pkcs12,
    ClientIdentity,
};
pub use client::MumbleClient;
pub use ping::ping_mumble_server;

#[derive(uniffi::Error, Debug, PartialEq)]
pub enum MumbleError {
    NetworkError(String),
    CertificateError(String),
    ProtocolError(String),
}

impl std::fmt::Display for MumbleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NetworkError(s) => write!(f, "Network error: {}", s),
            Self::CertificateError(s) => write!(f, "Certificate error: {}", s),
            Self::ProtocolError(s) => write!(f, "Protocol error: {}", s),
        }
    }
}

impl std::error::Error for MumbleError {}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum TalkingState {
    Passive,
    Talking,
    Whisper,
    Shout,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ChannelInfo {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub name: String,
    pub description: String,
    pub position: i32,
    pub is_temporary: bool,
    pub is_enter_restricted: bool,
    pub can_enter: bool,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct UserInfo {
    pub session_id: u32,
    pub channel_id: u32,
    pub name: String,
    pub is_muted: bool,
    pub is_deafened: bool,
    pub is_self_muted: bool,
    pub is_self_deafened: bool,
    pub is_priority_speaker: bool,
    pub is_recording: bool,
    pub comment: Option<String>,
    pub user_id: Option<u32>,
    pub is_talking: bool,
    pub talking_state: TalkingState,
    pub cert_hash: Option<String>,
    pub texture: Option<Vec<u8>>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ChatMessage {
    pub sender_session: u32,
    pub sender_name: String,
    pub channel_id: Option<u32>,
    pub recipient_session: Option<u32>,
    pub html_body: String,
    pub timestamp: u64,
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionStatus {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Failed,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct VoiceTargetConfig {
    pub id: u32,
    pub sessions: Vec<u32>,
    pub channel_id: Option<u32>,
    pub group: Option<String>,
    pub links: bool,
    pub children: bool,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ServerConnectionInfo {
    pub server_version: String,
    pub server_os: String,
    pub server_os_version: String,
    pub welcome_text: String,
    pub tls_cipher: String,
    pub max_bandwidth_kbps: u32,
    pub max_users: u32,
    pub using_udp_tunnel: bool,
    pub tcp_ping_ms: f32,
    pub udp_ping_ms: f32,
    pub good_packets: u32,
    pub late_packets: u32,
    pub lost_packets: u32,
    pub resync_packets: u32,
    pub udp_packets_sent: u32,
    pub tcp_packets_sent: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ServerPingInfo {
    pub latency_ms: f32,
    pub current_users: u32,
    pub max_users: u32,
    pub version: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct RegisteredUser {
    pub user_id: u32,
    pub name: String,
    pub last_seen: Option<String>,
    pub last_channel_id: Option<u32>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct BanEntryInfo {
    pub ip: String,
    pub mask: u32,
    pub name: String,
    pub hash: String,
    pub reason: String,
    pub start: String,
    pub duration: u32,
}

#[derive(uniffi::Record, Clone, Debug, Default, PartialEq)]
pub struct PacketStats {
    pub good: u32,
    pub late: u32,
    pub lost: u32,
    pub resync: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct UserStatsInfo {
    pub session_id: u32,
    pub user_name: String,
    pub version_v: String,
    pub version_os: String,
    pub version_os_version: String,
    pub version_release: String,
    pub ip_address: String,
    pub certificate_name: String,
    pub certificate_details: String,
    pub certificate_der: Option<Vec<u8>>,
    pub strong_certificate: bool,
    pub opus_supported: bool,
    pub tcp_ping_avg: f32,
    pub tcp_ping_var: f32,
    pub udp_ping_avg: f32,
    pub udp_ping_var: f32,
    pub tcp_packets: u32,
    pub udp_packets: u32,
    pub from_client: PacketStats,
    pub from_server: PacketStats,
    pub bandwidth: u32,
    pub onlinesecs: u32,
    pub idlesecs: u32,
}

#[uniffi::export(callback_interface)]
pub trait MumbleEventHandler: Send + Sync {
    fn on_connection_status_changed(&self, status: ConnectionStatus);
    fn on_channels_updated(&self, channels: Vec<ChannelInfo>);
    fn on_users_updated(&self, users: Vec<UserInfo>);
    fn on_user_talking_changed(&self, session_id: u32, is_talking: bool, talking_state: TalkingState);
    fn on_chat_message(&self, message: ChatMessage);
    fn on_ping_updated(&self, tcp_ms: f32, udp_ms: f32, using_udp_tunnel: bool);
    fn on_server_connection_info_updated(&self, info: ServerConnectionInfo);
    fn on_registered_users_updated(&self, users: Vec<RegisteredUser>);
    fn on_ban_list_updated(&self, bans: Vec<BanEntryInfo>);
    fn on_user_stats_received(&self, stats: UserStatsInfo);
}


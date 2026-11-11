uniffi::setup_scaffolding!();

pub mod proto {
    include!(concat!(env!("OUT_DIR"), "/mumble_proto.rs"));
}

pub mod udp_proto {
    include!(concat!(env!("OUT_DIR"), "/mumble_udp.rs"));
}

pub mod audio_io;
pub mod audio_mixer;
pub mod cert;
pub mod client;
pub mod connection;
pub mod crypt_ocb2;
pub mod dns;
pub mod framing;
pub mod ping;
pub mod plugins;
pub mod positional;
pub mod rpc;
pub mod state;
pub mod voice_packet;

pub use cert::{
    export_identity_to_pkcs12, generate_client_identity, import_identity_from_pkcs12,
    ClientIdentity,
};
pub use client::MumbleClient;
pub use dns::{resolve_mumble_srv, ResolvedEndpoint};
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
pub struct ServerIdentityChallenge {
    pub host: String,
    pub port: u16,
    pub fingerprint: String,
    pub previous_fingerprint: Option<String>,
    pub reason: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ChannelAclEntry {
    pub apply_here: bool,
    pub apply_subs: bool,
    pub inherited: bool,
    pub user_id: Option<u32>,
    pub group: Option<String>,
    pub grant: u32,
    pub deny: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ChannelAclGroup {
    pub name: String,
    pub inherited: bool,
    pub inherit: bool,
    pub inheritable: bool,
    pub add: Vec<u32>,
    pub remove: Vec<u32>,
    pub inherited_members: Vec<u32>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ChannelAcl {
    pub channel_id: u32,
    pub inherit_acls: bool,
    pub groups: Vec<ChannelAclGroup>,
    pub entries: Vec<ChannelAclEntry>,
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
    pub permissions: Option<u32>,
    pub links: Vec<u32>,
    pub max_users: u32,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct UserInfo {
    pub session_id: u32,
    pub channel_id: u32,
    pub name: String,
    pub is_muted: bool,
    pub is_suppressed: bool,
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
    pub listening_channels: Vec<u32>,
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
    /// Packet statistics reported by the server: what it received from us.
    pub good_packets: u32,
    pub late_packets: u32,
    pub lost_packets: u32,
    pub resync_packets: u32,
    /// Local statistics: what this client received from the server.
    pub local_good_packets: u32,
    pub local_late_packets: u32,
    pub local_lost_packets: u32,
    pub local_resync_packets: u32,
    pub udp_packets_sent: u32,
    pub tcp_packets_sent: u32,
    /// Server policy: false when the server forbids clients from recording.
    pub recording_allowed: bool,
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

/// Why a connection attempt or an established connection failed.
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionErrorKind {
    /// Host name could not be resolved or no endpoint was reachable.
    Unreachable,
    /// TCP/TLS handshake failed or timed out.
    Tls,
    /// The server did not finish authentication/synchronization in time.
    HandshakeTimeout,
    /// The server rejected the connection (see message for the reason).
    Rejected,
    /// Reading from or writing to the socket failed or stalled.
    Io,
}

#[uniffi::export(callback_interface)]
pub trait MumbleEventHandler: Send + Sync {
    fn on_server_identity_challenge(&self, challenge: ServerIdentityChallenge);
    fn on_channel_acl_received(&self, acl: ChannelAcl);
    fn on_connection_status_changed(&self, status: ConnectionStatus);
    fn on_channels_updated(&self, channels: Vec<ChannelInfo>);
    fn on_users_updated(&self, users: Vec<UserInfo>);
    fn on_user_talking_changed(
        &self,
        session_id: u32,
        is_talking: bool,
        talking_state: TalkingState,
    );
    fn on_chat_message(&self, message: ChatMessage);
    fn on_ping_updated(&self, tcp_ms: f32, udp_ms: f32, using_udp_tunnel: bool);
    fn on_server_connection_info_updated(&self, info: ServerConnectionInfo);
    fn on_registered_users_updated(&self, users: Vec<RegisteredUser>);
    fn on_ban_list_updated(&self, bans: Vec<BanEntryInfo>);
    fn on_user_stats_received(&self, stats: UserStatsInfo);
    /// A connection attempt or session ended abnormally.
    fn on_connection_error(&self, kind: ConnectionErrorKind, message: String);
    /// A control command could not be queued for sending (queue full or no connection).
    fn on_command_failed(&self, command: String, reason: String);
}

/// Forwards events only while `generation` still equals the generation this
/// connection was created with, so tasks of a replaced or closed connection can
/// never update the UI for a newer session.
pub(crate) struct GatedHandler {
    pub inner: std::sync::Arc<dyn MumbleEventHandler>,
    pub current: std::sync::Arc<std::sync::atomic::AtomicU64>,
    pub mine: u64,
}

impl GatedHandler {
    fn live(&self) -> bool {
        self.current.load(std::sync::atomic::Ordering::SeqCst) == self.mine
    }
}

impl MumbleEventHandler for GatedHandler {
    fn on_server_identity_challenge(&self, c: ServerIdentityChallenge) { if self.live() { self.inner.on_server_identity_challenge(c) } }
    fn on_channel_acl_received(&self, a: ChannelAcl) { if self.live() { self.inner.on_channel_acl_received(a) } }
    fn on_connection_status_changed(&self, s: ConnectionStatus) { if self.live() { self.inner.on_connection_status_changed(s) } }
    fn on_channels_updated(&self, c: Vec<ChannelInfo>) { if self.live() { self.inner.on_channels_updated(c) } }
    fn on_users_updated(&self, u: Vec<UserInfo>) { if self.live() { self.inner.on_users_updated(u) } }
    fn on_user_talking_changed(&self, s: u32, t: bool, st: TalkingState) { if self.live() { self.inner.on_user_talking_changed(s, t, st) } }
    fn on_chat_message(&self, m: ChatMessage) { if self.live() { self.inner.on_chat_message(m) } }
    fn on_ping_updated(&self, t: f32, u: f32, tun: bool) { if self.live() { self.inner.on_ping_updated(t, u, tun) } }
    fn on_server_connection_info_updated(&self, i: ServerConnectionInfo) { if self.live() { self.inner.on_server_connection_info_updated(i) } }
    fn on_registered_users_updated(&self, u: Vec<RegisteredUser>) { if self.live() { self.inner.on_registered_users_updated(u) } }
    fn on_ban_list_updated(&self, b: Vec<BanEntryInfo>) { if self.live() { self.inner.on_ban_list_updated(b) } }
    fn on_user_stats_received(&self, s: UserStatsInfo) { if self.live() { self.inner.on_user_stats_received(s) } }
    fn on_connection_error(&self, k: ConnectionErrorKind, m: String) { if self.live() { self.inner.on_connection_error(k, m) } }
    fn on_command_failed(&self, c: String, r: String) { if self.live() { self.inner.on_command_failed(c, r) } }
}

#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct AudioMetrics {
    pub mic_db: f32,
    pub mic_frames_processed: u64,
    pub transmitting: bool,
    pub mic_samples: Vec<f32>,
    pub speaker_samples: Vec<f32>,
    pub capture_overruns: u64,
    pub playback_underruns: u64,
}

#[cfg(test)]
mod gate_tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
    use std::sync::Arc;

    #[derive(Default)]
    struct Count(AtomicUsize);
    impl MumbleEventHandler for Count {
        fn on_server_identity_challenge(&self, _: ServerIdentityChallenge) {}
        fn on_channel_acl_received(&self, _: ChannelAcl) {}
        fn on_connection_status_changed(&self, _: ConnectionStatus) { self.0.fetch_add(1, Ordering::SeqCst); }
        fn on_channels_updated(&self, _: Vec<ChannelInfo>) { self.0.fetch_add(1, Ordering::SeqCst); }
        fn on_users_updated(&self, _: Vec<UserInfo>) {}
        fn on_user_talking_changed(&self, _: u32, _: bool, _: TalkingState) {}
        fn on_chat_message(&self, _: ChatMessage) { self.0.fetch_add(1, Ordering::SeqCst); }
        fn on_ping_updated(&self, _: f32, _: f32, _: bool) {}
        fn on_server_connection_info_updated(&self, _: ServerConnectionInfo) {}
        fn on_registered_users_updated(&self, _: Vec<RegisteredUser>) {}
        fn on_ban_list_updated(&self, _: Vec<BanEntryInfo>) {}
        fn on_user_stats_received(&self, _: UserStatsInfo) {}
        fn on_connection_error(&self, _: ConnectionErrorKind, _: String) { self.0.fetch_add(1, Ordering::SeqCst); }
        fn on_command_failed(&self, _: String, _: String) {}
    }

    #[test]
    fn events_of_a_replaced_connection_are_dropped() {
        let inner = Arc::new(Count::default());
        let current = Arc::new(AtomicU64::new(1));
        let old = GatedHandler { inner: inner.clone(), current: current.clone(), mine: 1 };
        old.on_connection_status_changed(ConnectionStatus::Connected);
        assert_eq!(inner.0.load(Ordering::SeqCst), 1);
        current.store(2, Ordering::SeqCst); // a newer connect()/disconnect() happened
        old.on_connection_status_changed(ConnectionStatus::Disconnected);
        old.on_channels_updated(vec![]);
        old.on_connection_error(ConnectionErrorKind::Io, "late".into());
        assert_eq!(inner.0.load(Ordering::SeqCst), 1, "stale session must not reach the UI");
        let new = GatedHandler { inner: inner.clone(), current, mine: 2 };
        new.on_channels_updated(vec![]);
        assert_eq!(inner.0.load(Ordering::SeqCst), 2);
    }
}

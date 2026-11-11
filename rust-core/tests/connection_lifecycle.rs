//! Deterministic connection-lifecycle tests against an in-process mock Mumble
//! server (TLS + control protocol + UDP), so races and failure modes that a
//! real Murmur cannot be told to produce can be exercised reliably.

use mumble_core::connection::certificate_fingerprint;
use mumble_core::crypt_ocb2::CryptStateOCB2;
use mumble_core::framing::*;
use mumble_core::proto;
use mumble_core::{
    BanEntryInfo, ChannelAcl, ChannelInfo, ChatMessage, ConnectionErrorKind, ConnectionStatus,
    MumbleClient, MumbleEventHandler, RegisteredUser, ServerConnectionInfo,
    ServerIdentityChallenge, TalkingState, UserInfo, UserStatsInfo,
};
use prost::Message;
use rustls::pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::net::{TcpListener, UdpSocket};
use tokio_rustls::TlsAcceptor;

// ---------------------------------------------------------------- recorder

#[derive(Debug, Clone, PartialEq)]
enum Ev {
    Status(ConnectionStatus),
    Error(ConnectionErrorKind, String),
    Channels(Vec<String>),
    CommandFailed(String, String),
    Ping(f32, f32),
}

#[derive(Default, Clone)]
struct Recorder(Arc<Mutex<Vec<Ev>>>);

impl Recorder {
    fn push(&self, e: Ev) {
        self.0.lock().unwrap().push(e);
    }
    fn all(&self) -> Vec<Ev> {
        self.0.lock().unwrap().clone()
    }
    fn len(&self) -> usize {
        self.0.lock().unwrap().len()
    }
    fn last_status(&self) -> Option<ConnectionStatus> {
        self.all().iter().rev().find_map(|e| match e {
            Ev::Status(s) => Some(*s),
            _ => None,
        })
    }
}

impl MumbleEventHandler for Recorder {
    fn on_server_identity_challenge(&self, c: ServerIdentityChallenge) {
        panic!("unexpected identity challenge: {c:?}");
    }
    fn on_channel_acl_received(&self, _: ChannelAcl) {}
    fn on_connection_status_changed(&self, s: ConnectionStatus) {
        self.push(Ev::Status(s));
    }
    fn on_channels_updated(&self, c: Vec<ChannelInfo>) {
        self.push(Ev::Channels(c.into_iter().map(|c| c.name).collect()));
    }
    fn on_users_updated(&self, _: Vec<UserInfo>) {}
    fn on_user_talking_changed(&self, _: u32, _: bool, _: TalkingState) {}
    fn on_chat_message(&self, _: ChatMessage) {}
    fn on_ping_updated(&self, t: f32, u: f32, _: bool) {
        self.push(Ev::Ping(t, u));
    }
    fn on_server_connection_info_updated(&self, _: ServerConnectionInfo) {}
    fn on_registered_users_updated(&self, _: Vec<RegisteredUser>) {}
    fn on_ban_list_updated(&self, _: Vec<BanEntryInfo>) {}
    fn on_user_stats_received(&self, _: UserStatsInfo) {}
    fn on_connection_error(&self, k: ConnectionErrorKind, m: String) {
        self.push(Ev::Error(k, m));
    }
    fn on_command_failed(&self, c: String, r: String) {
        self.push(Ev::CommandFailed(c, r));
    }
}

async fn eventually(what: &str, secs: u64, mut ok: impl FnMut() -> bool) {
    let end = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < end {
        if ok() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("timed out waiting for: {what}");
}

// ------------------------------------------------------------- mock server

#[derive(Clone)]
enum Behavior {
    /// Reads Version+Authenticate, then only sends Pings: never ServerSync.
    NeverSync,
    Reject,
    /// Normal login. `spam` re-sends a channel with that name every 20 ms.
    Sync {
        root_name: &'static str,
        spam: Option<&'static str>,
        recording_allowed: Option<bool>,
        crypt: bool,
    },
    /// Completes login and then never reads another byte.
    StallAfterSync,
}

struct Mock {
    port: u16,
    fingerprint: String,
    udp_received: Arc<Mutex<Vec<Vec<u8>>>>,
}

fn pkt<M: Message>(t: u16, m: &M) -> (u16, Vec<u8>) {
    (t, m.encode_to_vec())
}

async fn start_mock(behavior: Behavior) -> Mock {
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
    let ck = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
    let der = ck.cert.der().clone();
    let fingerprint = certificate_fingerprint(der.as_ref());
    let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(ck.key_pair.serialize_der()));
    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![der], key)
        .unwrap();
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    // UDP on the same port, IPv4 only: a lookup that picks ::1 would miss it.
    let udp = Arc::new(UdpSocket::bind(("127.0.0.1", port)).await.unwrap());
    let udp_received = Arc::new(Mutex::new(Vec::new()));
    let key16 = [0x42u8; 16];
    let client_nonce = [0x11u8; 16];
    let server_nonce = [0x22u8; 16];

    {
        let udp = Arc::clone(&udp);
        let sink = Arc::clone(&udp_received);
        let crypt_enabled = matches!(behavior, Behavior::Sync { crypt: true, .. });
        tokio::spawn(async move {
            // Server side of the OCB2 pair: encrypt with server nonce, decrypt with client nonce.
            let mut crypt = CryptStateOCB2::new(&key16, &server_nonce, &client_nonce);
            let mut buf = [0u8; 2048];
            loop {
                let Ok((n, from)) = udp.recv_from(&mut buf).await else { break };
                sink.lock().unwrap().push(buf[..n].to_vec());
                if !crypt_enabled {
                    continue;
                }
                let mut plain = [0u8; 2048];
                if let Ok(len) = crypt.decrypt(&buf[..n], &mut plain) {
                    // Echo the ping back (it is also a valid ping reply).
                    let mut out = vec![0u8; len + 4];
                    if let Ok(m) = crypt.encrypt(&plain[..len], &mut out) {
                        let _ = udp.send_to(&out[..m], from).await;
                    }
                }
            }
        });
    }

    tokio::spawn(async move {
        loop {
            let Ok((tcp, _)) = listener.accept().await else { break };
            let acceptor = acceptor.clone();
            let behavior = behavior.clone();
            tokio::spawn(async move {
                let Ok(tls) = acceptor.accept(tcp).await else { return };
                let (mut rd, mut wr) = tokio::io::split(tls);
                // Version + Authenticate
                for _ in 0..2 {
                    if read_packet(&mut rd).await.is_err() {
                        return;
                    }
                }
                match behavior {
                    Behavior::Reject => {
                        let r = proto::Reject { r#type: Some(3), reason: Some("nope".into()) };
                        let _ = write_raw_packet(&mut wr, TYPE_REJECT, &r.encode_to_vec()).await;
                        tokio::time::sleep(Duration::from_millis(200)).await;
                    }
                    Behavior::NeverSync => loop {
                        let p = proto::Ping { timestamp: Some(1), ..Default::default() };
                        if write_raw_packet(&mut wr, TYPE_PING, &p.encode_to_vec()).await.is_err() {
                            return;
                        }
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    },
                    Behavior::Sync { root_name, spam, recording_allowed, crypt } => {
                        let mut first: Vec<(u16, Vec<u8>)> = vec![pkt(
                            TYPE_CHANNEL_STATE,
                            &proto::ChannelState { channel_id: Some(0), name: Some(root_name.into()), ..Default::default() },
                        )];
                        if crypt {
                            first.push(pkt(
                                TYPE_CRYPT_SETUP,
                                &proto::CryptSetup {
                                    key: Some(key16.to_vec()),
                                    client_nonce: Some(client_nonce.to_vec()),
                                    server_nonce: Some(server_nonce.to_vec()),
                                },
                            ));
                        }
                        first.push(pkt(
                            TYPE_SERVER_SYNC,
                            &proto::ServerSync { session: Some(1), max_bandwidth: Some(72000), ..Default::default() },
                        ));
                        if let Some(allowed) = recording_allowed {
                            first.push(pkt(
                                TYPE_SERVER_CONFIG,
                                &proto::ServerConfig { recording_allowed: Some(allowed), ..Default::default() },
                            ));
                        }
                        for (t, p) in first {
                            if write_raw_packet(&mut wr, t, &p).await.is_err() {
                                return;
                            }
                        }
                        let mut tick = tokio::time::interval(Duration::from_millis(20));
                        loop {
                            tokio::select! {
                                _ = tick.tick(), if spam.is_some() => {
                                    let c = proto::ChannelState { channel_id: Some(99), name: spam.map(Into::into), ..Default::default() };
                                    if write_raw_packet(&mut wr, TYPE_CHANNEL_STATE, &c.encode_to_vec()).await.is_err() { return; }
                                }
                                r = read_packet(&mut rd) => {
                                    let Ok(p) = r else { return };
                                    if p.type_id == TYPE_PING {
                                        // Echo the timestamp like Murmur does.
                                        if write_raw_packet(&mut wr, TYPE_PING, &p.payload).await.is_err() { return; }
                                    }
                                }
                            }
                        }
                    }
                    Behavior::StallAfterSync => {
                        let s = proto::ServerSync { session: Some(1), max_bandwidth: Some(72000), ..Default::default() };
                        let _ = write_raw_packet(&mut wr, TYPE_SERVER_SYNC, &s.encode_to_vec()).await;
                        // Never read again: the client's writes will eventually block.
                        tokio::time::sleep(Duration::from_secs(60)).await;
                    }
                }
                drop((rd, wr));
            });
        }
    });
    Mock { port, fingerprint, udp_received }
}

fn client() -> (Arc<MumbleClient>, Recorder) {
    let rec = Recorder::default();
    (MumbleClient::new(Box::new(rec.clone())), rec)
}

fn connect(c: &MumbleClient, host: &str, m: &Mock) {
    c.connect(host.into(), m.port, "tester".into(), None, None, None, Some(m.fingerprint.clone()));
}

const SYNC: Behavior = Behavior::Sync { root_name: "Root", spam: None, recording_allowed: None, crypt: false };

// ------------------------------------------------------------------- tests

/// NET-06: a server that keeps the connection alive with Pings but never
/// completes login must not leave Connect pending forever.
#[tokio::test(flavor = "multi_thread")]
async fn handshake_deadline_ends_connect_even_while_pings_arrive() {
    let m = start_mock(Behavior::NeverSync).await;
    let (c, rec) = client();
    c.set_network_timeouts_ms(600, 10_000);
    connect(&c, "127.0.0.1", &m);
    eventually("handshake timeout error", 5, || {
        rec.all().iter().any(|e| matches!(e, Ev::Error(ConnectionErrorKind::HandshakeTimeout, _)))
    })
    .await;
    eventually("Failed status", 2, || rec.last_status() == Some(ConnectionStatus::Failed)).await;
    assert!(!c.disconnect_reason().is_empty(), "the user must be told why");
}

/// NET-05: a rejection is reported as Rejected, and the session ends as Failed
/// (not silently overwritten by Disconnected).
#[tokio::test(flavor = "multi_thread")]
async fn rejection_is_reported_and_ends_failed() {
    let m = start_mock(Behavior::Reject).await;
    let (c, rec) = client();
    connect(&c, "127.0.0.1", &m);
    eventually("reject error", 5, || {
        rec.all().iter().any(|e| matches!(e, Ev::Error(ConnectionErrorKind::Rejected, msg) if msg.contains("Wrong user password")))
    })
    .await;
    eventually("Failed status", 2, || rec.last_status() == Some(ConnectionStatus::Failed)).await;
    assert_eq!(c.get_connection_status(), ConnectionStatus::Failed);
}

/// NET-05: nothing listening -> a structured Unreachable error, not a bare Failed.
#[tokio::test(flavor = "multi_thread")]
async fn unreachable_server_reports_a_reason() {
    let (c, rec) = client();
    // Bind then drop to obtain a port that refuses connections.
    let port = TcpListener::bind("127.0.0.1:0").await.unwrap().local_addr().unwrap().port();
    c.connect("127.0.0.1".into(), port, "t".into(), None, None, None, None);
    eventually("unreachable error", 8, || {
        rec.all().iter().any(|e| matches!(e, Ev::Error(ConnectionErrorKind::Unreachable, _)))
    })
    .await;
    assert_eq!(rec.last_status(), Some(ConnectionStatus::Failed));
}

/// NET-02: after switching A -> B, nothing from A may reach the UI or B's state.
#[tokio::test(flavor = "multi_thread")]
async fn switching_servers_silences_the_old_session() {
    let a = start_mock(Behavior::Sync { root_name: "A-root", spam: Some("A-late"), recording_allowed: None, crypt: false }).await;
    let b = start_mock(Behavior::Sync { root_name: "B-root", spam: None, recording_allowed: None, crypt: false }).await;
    let (c, rec) = client();
    connect(&c, "127.0.0.1", &a);
    eventually("A connected and chattering", 5, || {
        rec.all().iter().any(|e| matches!(e, Ev::Channels(n) if n.iter().any(|x| x == "A-late")))
    })
    .await;
    let gen_a = c.connection_generation();
    connect(&c, "127.0.0.1", &b);
    assert!(c.connection_generation() > gen_a);
    let mark = rec.len(); // everything from the A->B switch itself is before this
    eventually("B connected", 5, || rec.last_status() == Some(ConnectionStatus::Connected)).await;
    tokio::time::sleep(Duration::from_millis(500)).await; // A would have sent ~25 more updates
    let after: Vec<_> = rec.all().into_iter().skip(mark).collect();
    assert!(
        !after.iter().any(|e| matches!(e, Ev::Channels(n) if n.iter().any(|x| x == "A-late" || x == "A-root"))),
        "stale events from A reached the client: {after:?}"
    );
    let names: Vec<String> = c.get_channels().into_iter().map(|c| c.name).collect();
    assert_eq!(names, vec!["B-root".to_string()], "B's channel list must contain only B's data");
}

/// NET-02: rapid repeated Connect/Disconnect settles on the last request only.
#[tokio::test(flavor = "multi_thread")]
async fn rapid_reconnect_settles_on_the_last_request() {
    let a = start_mock(SYNC).await;
    let b = start_mock(Behavior::Sync { root_name: "B-root", spam: None, recording_allowed: None, crypt: false }).await;
    let (c, rec) = client();
    for _ in 0..5 {
        connect(&c, "127.0.0.1", &a);
        connect(&c, "127.0.0.1", &b);
        c.disconnect();
    }
    connect(&c, "127.0.0.1", &b);
    eventually("connected to B", 5, || {
        c.get_connection_status() == ConnectionStatus::Connected
            && c.get_channels().iter().any(|ch| ch.name == "B-root")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(c.get_connection_status(), ConnectionStatus::Connected);
    assert_eq!(c.get_channels().len(), 1);
    assert_eq!(rec.last_status(), Some(ConnectionStatus::Connected));
}

/// NET-01: session-scoped state does not survive into the next connection.
#[tokio::test(flavor = "multi_thread")]
async fn reconnect_clears_session_scoped_state() {
    let a = start_mock(SYNC).await;
    let (c, _rec) = client();
    connect(&c, "127.0.0.1", &a);
    eventually("connected", 5, || c.get_connection_status() == ConnectionStatus::Connected).await;
    c.set_user_local_volume(7, 0.1);
    c.set_voice_target(mumble_core::VoiceTargetConfig { id: 3, sessions: vec![9], channel_id: None, group: None, links: false, children: false });
    c.set_active_voice_target_id(3);
    assert_eq!(c.get_active_voice_target_id(), 3);
    connect(&c, "127.0.0.1", &a);
    assert_eq!(c.get_active_voice_target_id(), 0, "a whisper target must not outlive its session");
    eventually("reconnected", 5, || c.get_connection_status() == ConnectionStatus::Connected).await;
}

/// NET-03: UDP must go to the exact peer that accepted TCP. The mock listens on
/// 127.0.0.1 only; connecting through "localhost" (which may resolve to ::1
/// first) must still deliver the UDP datagram there.
#[tokio::test(flavor = "multi_thread")]
async fn udp_uses_the_established_tcp_peer() {
    let m = start_mock(Behavior::Sync { root_name: "Root", spam: None, recording_allowed: None, crypt: true }).await;
    let (c, _rec) = client();
    connect(&c, "localhost", &m);
    eventually("UDP datagram at the TCP peer", 8, || !m.udp_received.lock().unwrap().is_empty()).await;
}

/// NET-04: a UDP reply must not reset the TCP latency, and vice versa.
#[tokio::test(flavor = "multi_thread")]
async fn udp_ping_reply_keeps_the_tcp_measurement() {
    let m = start_mock(Behavior::Sync { root_name: "Root", spam: None, recording_allowed: None, crypt: true }).await;
    let (c, rec) = client();
    connect(&c, "127.0.0.1", &m);
    // UDP pings go out immediately; the first TCP ping goes out after ~5 s.
    eventually("udp sample", 8, || rec.all().iter().any(|e| matches!(e, Ev::Ping(_, u) if *u > 0.0))).await;
    eventually("tcp sample", 12, || rec.all().iter().any(|e| matches!(e, Ev::Ping(t, _) if *t > 0.0))).await;
    let events = rec.all();
    let first_tcp = events.iter().position(|e| matches!(e, Ev::Ping(t, _) if *t > 0.0)).unwrap();
    // Wait for another UDP reply after the TCP sample, if one arrives in time.
    tokio::time::sleep(Duration::from_secs(1)).await;
    for e in rec.all().iter().skip(first_tcp) {
        if let Ev::Ping(t, _) = e {
            assert!(*t > 0.0, "TCP latency was reset to zero by a later event: {e:?}");
        }
    }
    let info = c.get_server_connection_info();
    assert!(info.tcp_ping_ms > 0.0 && info.udp_ping_ms > 0.0, "both measurements kept: {info:?}");
}

/// NET-06: a peer that stops reading must end the session promptly instead of
/// leaving it half-alive; NET-05: dropped commands are reported.
#[tokio::test(flavor = "multi_thread")]
async fn stalled_writer_wakes_the_session_and_overflow_is_reported() {
    let m = start_mock(Behavior::StallAfterSync).await;
    let (c, rec) = client();
    c.set_network_timeouts_ms(30_000, 400);
    connect(&c, "127.0.0.1", &m);
    eventually("connected", 5, || c.get_connection_status() == ConnectionStatus::Connected).await;
    let big = "x".repeat(60_000);
    let end = Instant::now() + Duration::from_secs(20);
    while c.get_connection_status() == ConnectionStatus::Connected && Instant::now() < end {
        for _ in 0..40 {
            c.send_chat_message(0, big.clone());
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_ne!(c.get_connection_status(), ConnectionStatus::Connected, "writer stall must end the session");
    assert!(rec.all().iter().any(|e| matches!(e, Ev::Error(ConnectionErrorKind::Io, _))), "{:?}", rec.all().iter().filter(|e| !matches!(e, Ev::CommandFailed(..))).collect::<Vec<_>>());
    assert!(rec.all().iter().any(|e| matches!(e, Ev::CommandFailed(_, r) if r.contains("full") || r.contains("closed") || r.contains("not connected"))));
}

/// PRO-01: the server's recording policy is honoured.
#[tokio::test(flavor = "multi_thread")]
async fn recording_follows_server_policy() {
    let dir = tempfile::tempdir().unwrap();
    let denied = start_mock(Behavior::Sync { root_name: "Root", spam: None, recording_allowed: Some(false), crypt: false }).await;
    let (c, _rec) = client();
    connect(&c, "127.0.0.1", &denied);
    eventually("policy received", 5, || !c.recording_allowed()).await;
    assert!(!c.start_recording(dir.path().join("denied.wav").to_string_lossy().into()));
    assert!(!c.get_server_connection_info().recording_allowed);

    let allowed = start_mock(Behavior::Sync { root_name: "Root", spam: None, recording_allowed: Some(true), crypt: false }).await;
    connect(&c, "127.0.0.1", &allowed);
    eventually("connected", 5, || c.get_connection_status() == ConnectionStatus::Connected).await;
    assert!(c.recording_allowed(), "policy must not leak across connections");
    assert!(c.start_recording(dir.path().join("ok.wav").to_string_lossy().into()));
    c.stop_recording();
}

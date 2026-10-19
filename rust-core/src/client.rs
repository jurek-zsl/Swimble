use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::io::AsyncWriteExt;
use tokio::net::UdpSocket;
use tokio::sync::{mpsc, watch};
use prost::Message;

use crate::audio_mixer::AudioMixer;
use crate::connection::connect_tls;
use crate::crypt_ocb2::CryptStateOCB2;
use crate::framing::{
    read_packet, write_raw_packet,
    TYPE_AUTHENTICATE, TYPE_BAN_LIST, TYPE_CHANNEL_REMOVE, TYPE_CHANNEL_STATE, TYPE_CRYPT_SETUP,
    TYPE_PERMISSION_DENIED, TYPE_PERMISSION_QUERY, TYPE_PING, TYPE_REJECT, TYPE_REQUEST_BLOB,
    TYPE_SERVER_CONFIG, TYPE_SERVER_SYNC,
    TYPE_TEXT_MESSAGE, TYPE_UDP_TUNNEL, TYPE_USER_LIST, TYPE_USER_REMOVE, TYPE_USER_STATE,
    TYPE_USER_STATS, TYPE_VERSION, TYPE_VOICE_TARGET,
};
use crate::proto;
use crate::state::ClientState;
use crate::voice_packet::{
    decode_server_voice, decode_udp_ping_reply, encode_client_voice, encode_udp_ping,
};
use crate::{
    BanEntryInfo, ChannelInfo, ChatMessage, ConnectionStatus, MumbleEventHandler, PacketStats,
    RegisteredUser, ServerConnectionInfo, UserInfo, UserStatsInfo, VoiceTargetConfig,
};

fn is_ipv4_mapped(addr: &[u8]) -> bool {
    if addr.len() != 16 {
        return false;
    }
    addr[0..10].iter().all(|&b| b == 0) && addr[10] == 0xff && addr[11] == 0xff
}

fn decode_ban_ip(addr: &[u8]) -> String {
    if addr.len() == 16 {
        if is_ipv4_mapped(addr) {
            format!("{}.{}.{}.{}", addr[12], addr[13], addr[14], addr[15])
        } else {
            let mut octets = [0u8; 16];
            octets.copy_from_slice(addr);
            std::net::Ipv6Addr::from(octets).to_string()
        }
    } else if addr.len() == 4 {
        format!("{}.{}.{}.{}", addr[0], addr[1], addr[2], addr[3])
    } else {
        String::new()
    }
}

fn encode_ban_ip(ip: &str, mask: u32) -> (Vec<u8>, u32) {
    let trimmed = ip.trim();
    if let Ok(ipv4) = trimmed.parse::<std::net::Ipv4Addr>() {
        let octets = ipv4.octets();
        let mut bytes = vec![0u8; 16];
        bytes[10] = 0xff;
        bytes[11] = 0xff;
        bytes[12..16].copy_from_slice(&octets);
        let effective_mask = if mask <= 32 { 96 + mask } else { 128 };
        (bytes, effective_mask)
    } else if let Ok(ipv6) = trimmed.parse::<std::net::Ipv6Addr>() {
        let bytes = ipv6.octets().to_vec();
        let effective_mask = if mask <= 128 { mask } else { 128 };
        (bytes, effective_mask)
    } else {
        (vec![0u8; 16], 128)
    }
}

pub struct TokioRunner {
    handle: tokio::runtime::Handle,
    _runtime: Option<tokio::runtime::Runtime>,
}

impl TokioRunner {
    pub fn new() -> Self {
        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            Self {
                handle,
                _runtime: None,
            }
        } else {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .expect("Failed to build Tokio runtime");
            let handle = rt.handle().clone();
            Self {
                handle,
                _runtime: Some(rt),
            }
        }
    }

    pub fn spawn<F>(&self, future: F) -> tokio::task::JoinHandle<F::Output>
    where
        F: std::future::Future + Send + 'static,
        F::Output: Send + 'static,
    {
        self.handle.spawn(future)
    }
}

pub enum OutgoingCommand {
    Proto(u16, Vec<u8>),
    Disconnect,
}

#[derive(uniffi::Object)]
pub struct MumbleClient {
    handler: Arc<dyn MumbleEventHandler>,
    state: Arc<RwLock<ClientState>>,
    command_tx: Arc<RwLock<Option<mpsc::Sender<OutgoingCommand>>>>,
    voice_tx: Arc<RwLock<Option<mpsc::Sender<Vec<u8>>>>>,
    shutdown_tx: Arc<RwLock<Option<watch::Sender<bool>>>>,
    runner: Arc<TokioRunner>,
    audio_mixer: Arc<Mutex<AudioMixer>>,
    speaker_consumer: Arc<Mutex<rtrb::Consumer<f32>>>,
    last_udp_ping_received: Arc<RwLock<Instant>>,
    crypt_state: Arc<Mutex<Option<CryptStateOCB2>>>,
    tokens: Arc<RwLock<Vec<String>>>,
    active_voice_target_id: Arc<RwLock<u8>>,
    tcp_packets_sent: Arc<AtomicU32>,
    udp_packets_sent: Arc<AtomicU32>,
    self_priority_transmitting: Arc<AtomicBool>,
}

#[uniffi::export]
impl MumbleClient {
    #[uniffi::constructor]
    pub fn new(handler: Box<dyn MumbleEventHandler>) -> Arc<Self> {
        let (speaker_producer, speaker_consumer) = rtrb::RingBuffer::<f32>::new(48000 * 2);
        let audio_mixer = AudioMixer::new(speaker_producer).expect("Failed to initialize AudioMixer");

        Arc::new(Self {
            handler: handler.into(),
            state: Arc::new(RwLock::new(ClientState::new())),
            command_tx: Arc::new(RwLock::new(None)),
            voice_tx: Arc::new(RwLock::new(None)),
            shutdown_tx: Arc::new(RwLock::new(None)),
            runner: Arc::new(TokioRunner::new()),
            audio_mixer: Arc::new(Mutex::new(audio_mixer)),
            speaker_consumer: Arc::new(Mutex::new(speaker_consumer)),
            last_udp_ping_received: Arc::new(RwLock::new(
                Instant::now().checked_sub(Duration::from_secs(60)).unwrap_or_else(Instant::now),
            )),
            crypt_state: Arc::new(Mutex::new(None)),
            tokens: Arc::new(RwLock::new(Vec::new())),
            active_voice_target_id: Arc::new(RwLock::new(0)),
            tcp_packets_sent: Arc::new(AtomicU32::new(0)),
            udp_packets_sent: Arc::new(AtomicU32::new(0)),
            self_priority_transmitting: Arc::new(AtomicBool::new(false)),
        })
    }

    pub fn connect(
        &self,
        host: String,
        port: u16,
        username: String,
        password: Option<String>,
        client_cert_pem: Option<String>,
        client_key_pem: Option<String>,
    ) {
        self.disconnect();

        {
            let mut state = self.state.write().unwrap();
            state.reset();
            state.connection_status = ConnectionStatus::Connecting;
        }
        self.handler
            .on_connection_status_changed(ConnectionStatus::Connecting);

        let (cmd_tx, mut cmd_rx) = mpsc::channel::<OutgoingCommand>(128);
        let (voice_tx, mut voice_rx) = mpsc::channel::<Vec<u8>>(128);
        let (shutdown_tx, mut shutdown_rx) = watch::channel(false);

        *self.command_tx.write().unwrap() = Some(cmd_tx.clone());
        *self.voice_tx.write().unwrap() = Some(voice_tx);
        *self.shutdown_tx.write().unwrap() = Some(shutdown_tx);
        *self.crypt_state.lock().unwrap() = None;
        *self.last_udp_ping_received.write().unwrap() =
            Instant::now().checked_sub(Duration::from_secs(60)).unwrap_or_else(Instant::now);
        self.tcp_packets_sent.store(0, Ordering::Relaxed);
        self.udp_packets_sent.store(0, Ordering::Relaxed);
        self.self_priority_transmitting.store(false, Ordering::Relaxed);

        let state_arc = Arc::clone(&self.state);
        let handler_arc = Arc::clone(&self.handler);
        let runner_arc = Arc::clone(&self.runner);
        let mixer_arc = Arc::clone(&self.audio_mixer);
        let crypt_arc = Arc::clone(&self.crypt_state);
        let last_udp_ping_arc = Arc::clone(&self.last_udp_ping_received);
        let tcp_sent_arc = Arc::clone(&self.tcp_packets_sent);
        let udp_sent_arc = Arc::clone(&self.udp_packets_sent);
        let self_priority_for_udp = Arc::clone(&self.self_priority_transmitting);
        let self_priority_for_tcp = Arc::clone(&self.self_priority_transmitting);

        let host_for_udp = host.clone();
        let initial_tokens = self.tokens.read().unwrap().clone();

        self.runner.spawn(async move {
            let tls_stream = match connect_tls(
                &host,
                port,
                client_cert_pem.as_deref(),
                client_key_pem.as_deref(),
            )
            .await
            {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Mumble TLS connection error: {:?}", e);
                    state_arc.write().unwrap().connection_status = ConnectionStatus::Failed;
                    handler_arc.on_connection_status_changed(ConnectionStatus::Failed);
                    return;
                }
            };

            let cipher_name = tls_stream
                .get_ref()
                .1
                .negotiated_cipher_suite()
                .map(|cs| format!("{:?}", cs.suite()))
                .unwrap_or_else(|| "TLS_AES_256_GCM_SHA384".to_string());
            state_arc.write().unwrap().server_info.tls_cipher = cipher_name;

            let (mut reader, mut writer) = tokio::io::split(tls_stream);

            // Send Version (packet type 0)
            let version = proto::Version {
                version_v1: Some((1 << 16) | (5 << 8) | 0), // 1.5.0
                version_v2: Some((1 << 48) | (5 << 32) | 0),
                release: Some("Swimble 1.0.0".to_string()),
                os: Some("macOS".to_string()),
                os_version: Some("26.0".to_string()),
            };
            if let Err(e) =
                write_raw_packet(&mut writer, TYPE_VERSION, &version.encode_to_vec()).await
            {
                eprintln!("Failed to send Version packet: {:?}", e);
                state_arc.write().unwrap().connection_status = ConnectionStatus::Failed;
                handler_arc.on_connection_status_changed(ConnectionStatus::Failed);
                return;
            }

            // Send Authenticate (packet type 2)
            let auth = proto::Authenticate {
                username: Some(username),
                password,
                tokens: initial_tokens,
                celt_versions: vec![],
                opus: Some(true),
                client_type: Some(0),
            };
            if let Err(e) =
                write_raw_packet(&mut writer, TYPE_AUTHENTICATE, &auth.encode_to_vec()).await
            {
                eprintln!("Failed to send Authenticate packet: {:?}", e);
                state_arc.write().unwrap().connection_status = ConnectionStatus::Failed;
                handler_arc.on_connection_status_changed(ConnectionStatus::Failed);
                return;
            }

            // TCP Heartbeat task: sends TCP Ping every 5 seconds
            let cmd_tx_heartbeat = cmd_tx.clone();
            let mut heartbeat_shutdown_rx = shutdown_rx.clone();
            runner_arc.spawn(async move {
                let mut interval = tokio::time::interval(Duration::from_secs(5));
                interval.tick().await;

                loop {
                    tokio::select! {
                        _ = interval.tick() => {
                            let now_timestamp = SystemTime::now()
                                .duration_since(UNIX_EPOCH)
                                .unwrap_or_default()
                                .as_micros() as u64;
                            let ping = proto::Ping {
                                timestamp: Some(now_timestamp),
                                ..Default::default()
                            };
                            let _ = cmd_tx_heartbeat.send(OutgoingCommand::Proto(TYPE_PING, ping.encode_to_vec())).await;
                        }
                        _ = heartbeat_shutdown_rx.changed() => {
                            break;
                        }
                    }
                }
            });

            // Talking timeout checker: runs every 100ms
            let mixer_timeout = Arc::clone(&mixer_arc);
            let handler_timeout = Arc::clone(&handler_arc);
            let state_timeout = Arc::clone(&state_arc);
            let mut timeout_shutdown_rx = shutdown_rx.clone();
            runner_arc.spawn(async move {
                let mut interval = tokio::time::interval(Duration::from_millis(100));
                loop {
                    tokio::select! {
                        _ = interval.tick() => {
                            let events = {
                                if let Ok(mut mixer) = mixer_timeout.lock() {
                                    mixer.check_talking_timeouts()
                                } else {
                                    vec![]
                                }
                            };
                            for (session_id, is_talking, talking_state) in events {
                                state_timeout.write().unwrap().set_user_talking(session_id, is_talking, talking_state);
                                handler_timeout.on_user_talking_changed(session_id, is_talking, talking_state);
                            }
                        }
                        _ = timeout_shutdown_rx.changed() => {
                            break;
                        }
                    }
                }
            });

            // TLS Writer task
            let mut writer_shutdown_rx = shutdown_rx.clone();
            let tcp_sent_writer = Arc::clone(&tcp_sent_arc);
            let writer_handle = runner_arc.spawn(async move {
                loop {
                    tokio::select! {
                        cmd = cmd_rx.recv() => {
                            match cmd {
                                Some(OutgoingCommand::Proto(type_id, payload)) => {
                                    tcp_sent_writer.fetch_add(1, Ordering::Relaxed);
                                    if let Err(e) = write_raw_packet(&mut writer, type_id, &payload).await {
                                        eprintln!("TLS write error: {:?}", e);
                                        break;
                                    }
                                }
                                Some(OutgoingCommand::Disconnect) | None => {
                                    let _ = writer.shutdown().await;
                                    break;
                                }
                            }
                        }
                        _ = writer_shutdown_rx.changed() => {
                            let _ = writer.shutdown().await;
                            break;
                        }
                    }
                }
            });

            // UDP socket instance shared between UDP senders and receiver
            let udp_socket_holder: Arc<RwLock<Option<Arc<UdpSocket>>>> =
                Arc::new(RwLock::new(None));
            let udp_holder_clone = Arc::clone(&udp_socket_holder);

            // Outgoing Voice Routing Task:
            // Checks if UDP is responsive (UDP ping received within 15 seconds).
            // If responsive, encrypts via OCB2 and sends over UDP socket.
            // Otherwise, falls back to sending raw voice packet inside TCP UDPTunnel (type 1) frames.
            let cmd_tx_voice = cmd_tx.clone();
            let last_ping_voice = Arc::clone(&last_udp_ping_arc);
            let crypt_voice = Arc::clone(&crypt_arc);
            let udp_sent_voice = Arc::clone(&udp_sent_arc);
            let mut voice_shutdown_rx = shutdown_rx.clone();

            runner_arc.spawn(async move {
                loop {
                    tokio::select! {
                        voice_data = voice_rx.recv() => {
                            let raw_voice = match voice_data {
                                Some(v) => v,
                                None => break,
                            };

                            let is_udp_active = last_ping_voice.read().unwrap().elapsed() < Duration::from_secs(15);
                            let maybe_udp = udp_holder_clone.read().unwrap().clone();

                            let mut sent_via_udp = false;
                            if is_udp_active {
                                if let Some(ref udp) = maybe_udp {
                                    let crypted_opt = {
                                        if let Some(ref mut crypt) = *crypt_voice.lock().unwrap() {
                                            let mut encrypted = vec![0u8; raw_voice.len() + 4];
                                            crypt.encrypt(&raw_voice, &mut encrypted).ok().map(|len| (encrypted, len))
                                        } else {
                                            None
                                        }
                                    };
                                    if let Some((encrypted, crypted_len)) = crypted_opt {
                                        if udp.send(&encrypted[..crypted_len]).await.is_ok() {
                                            udp_sent_voice.fetch_add(1, Ordering::Relaxed);
                                            sent_via_udp = true;
                                        }
                                    }
                                }
                            }

                            if !sent_via_udp {
                                // Fallback: Route voice packet inside TCP UDPTunnel frame
                                let _ = cmd_tx_voice.send(OutgoingCommand::Proto(TYPE_UDP_TUNNEL, raw_voice)).await;
                            }
                        }
                        _ = voice_shutdown_rx.changed() => {
                            break;
                        }
                    }
                }
            });

            // TLS Reader loop
            let cmd_tx_blob = cmd_tx.clone();
            loop {
                tokio::select! {
                    _ = shutdown_rx.changed() => {
                        break;
                    }
                    packet_res = read_packet(&mut reader) => {
                        let packet = match packet_res {
                            Ok(p) => p,
                            Err(e) => {
                                eprintln!("Mumble read error or disconnect: {:?}", e);
                                break;
                            }
                        };

                        match packet.type_id {
                            TYPE_SERVER_SYNC => {
                                if let Ok(sync) = proto::ServerSync::decode(&packet.payload[..]) {
                                    let (info, welcome_opt) = {
                                        let mut state = state_arc.write().unwrap();
                                        state.my_session = sync.session;
                                        state.connection_status = ConnectionStatus::Connected;
                                        state.is_synced = true;
                                        if let Some(max_band) = sync.max_bandwidth {
                                            state.server_info.max_bandwidth_kbps = max_band / 1000;
                                        }
                                        if let Some(ref welcome) = sync.welcome_text {
                                            if !welcome.is_empty() {
                                                state.server_info.welcome_text = welcome.clone();
                                            }
                                        }
                                        (state.server_info.clone(), sync.welcome_text)
                                    };
                                    handler_arc.on_connection_status_changed(ConnectionStatus::Connected);
                                    handler_arc.on_server_connection_info_updated(info);

                                    let timestamp = SystemTime::now()
                                        .duration_since(UNIX_EPOCH)
                                        .unwrap_or_default()
                                        .as_millis() as u64;
                                    let connect_msg = ChatMessage {
                                        sender_session: 0,
                                        sender_name: "System".to_string(),
                                        channel_id: None,
                                        recipient_session: None,
                                        html_body: "Connected to server.".to_string(),
                                        timestamp,
                                    };
                                    handler_arc.on_chat_message(connect_msg);

                                    if let Some(welcome) = welcome_opt {
                                        let trimmed = welcome.trim();
                                        if !trimmed.is_empty() {
                                            let chat = ChatMessage {
                                                sender_session: 0,
                                                sender_name: "Server".to_string(),
                                                channel_id: None,
                                                recipient_session: None,
                                                html_body: welcome,
                                                timestamp,
                                            };
                                            handler_arc.on_chat_message(chat);
                                        }
                                    }
                                }
                            }
                            TYPE_CHANNEL_STATE => {
                                if let Ok(cstate) = proto::ChannelState::decode(&packet.payload[..]) {
                                    let (ch_event_msg, channels) = {
                                        let mut state = state_arc.write().unwrap();
                                        let is_new = cstate.channel_id.map(|cid| !state.channels.contains_key(&cid)).unwrap_or(false);
                                        let prev_name = cstate.channel_id.and_then(|cid| state.channels.get(&cid).map(|c| c.name.clone()));
                                        state.update_channel(cstate.clone());
                                        let current_name = cstate.channel_id.and_then(|cid| state.channels.get(&cid).map(|c| c.name.clone())).unwrap_or_default();

                                        let msg = if state.is_synced {
                                            if is_new && !current_name.is_empty() {
                                                Some(format!("Channel '{}' created.", current_name))
                                            } else if let (Some(prev), Some(_cid)) = (prev_name, cstate.channel_id) {
                                                if let Some(ref new_n) = cstate.name {
                                                    if &prev != new_n {
                                                        Some(format!("Channel '{}' renamed to '{}'.", prev, new_n))
                                                    } else {
                                                        None
                                                    }
                                                } else {
                                                    None
                                                }
                                            } else {
                                                None
                                            }
                                        } else {
                                            None
                                        };
                                        (msg, state.channels_list())
                                    };
                                    if let Some(msg) = ch_event_msg {
                                        let timestamp = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_millis() as u64;
                                        let chat = ChatMessage {
                                            sender_session: 0,
                                            sender_name: "System".to_string(),
                                            channel_id: None,
                                            recipient_session: None,
                                            html_body: msg,
                                            timestamp,
                                        };
                                        handler_arc.on_chat_message(chat);
                                    }
                                    handler_arc.on_channels_updated(channels);

                                    // If description was not sent inline but hash was provided, request the full blob
                                    if cstate.description.is_none() {
                                        if let (Some(cid), Some(ref hash)) = (cstate.channel_id, &cstate.description_hash) {
                                            if !hash.is_empty() {
                                                let req = proto::RequestBlob {
                                                    channel_description: vec![cid],
                                                    ..Default::default()
                                                };
                                                let _ = cmd_tx_blob.try_send(OutgoingCommand::Proto(TYPE_REQUEST_BLOB, req.encode_to_vec()));
                                            }
                                        }
                                    }
                                }
                            }
                            TYPE_CHANNEL_REMOVE => {
                                if let Ok(cremove) = proto::ChannelRemove::decode(&packet.payload[..]) {
                                    let (ch_event_msg, channels) = {
                                        let mut state = state_arc.write().unwrap();
                                        let ch_name = state.channels.get(&cremove.channel_id).map(|c| c.name.clone());
                                        state.remove_channel(cremove.channel_id);
                                        let msg = if state.is_synced {
                                            ch_name.map(|name| format!("Channel '{}' removed.", name))
                                        } else {
                                            None
                                        };
                                        (msg, state.channels_list())
                                    };
                                    if let Some(msg) = ch_event_msg {
                                        let timestamp = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_millis() as u64;
                                        let chat = ChatMessage {
                                            sender_session: 0,
                                            sender_name: "System".to_string(),
                                            channel_id: None,
                                            recipient_session: None,
                                            html_body: msg,
                                            timestamp,
                                        };
                                        handler_arc.on_chat_message(chat);
                                    }
                                    handler_arc.on_channels_updated(channels);
                                }
                            }
                            TYPE_USER_STATE => {
                                if let Ok(ustate) = proto::UserState::decode(&packet.payload[..]) {
                                    let (user_event_msg, users) = {
                                        let mut state = state_arc.write().unwrap();
                                        let my_session = state.my_session;
                                        let session = ustate.session.unwrap_or(0);
                                        let prev_user = state.users.get(&session).cloned();
                                        let is_synced = state.is_synced;
                                        let target_name = prev_user.as_ref().map(|u| u.name.clone())
                                            .or_else(|| ustate.name.clone())
                                            .unwrap_or_else(|| format!("User #{}", session));
                                        let actor_name = ustate.actor.and_then(|a| state.users.get(&a).map(|u| u.name.clone()));

                                        let mut msg: Option<String> = None;

                                        if is_synced {
                                            if let Some(prev) = &prev_user {
                                                // Check admin action
                                                if let Some(actor) = &actor_name {
                                                    if ustate.actor != Some(session) {
                                                        if let Some(cid) = ustate.channel_id {
                                                            if cid != prev.channel_id {
                                                                let ch_name = state.channels.get(&cid).map(|c| c.name.clone()).unwrap_or_else(|| format!("Channel #{}", cid));
                                                                 if Some(session) == my_session {
                                                                    msg = Some(format!("You were moved to {} by {}.", ch_name, actor));
                                                                } else if ustate.actor == my_session {
                                                                    msg = Some(format!("You moved {} to {}.", target_name, ch_name));
                                                                } else {
                                                                    msg = Some(format!("{} moved {} to {}.", actor, target_name, ch_name));
                                                                }
                                                            }
                                                        }
                                                        if let Some(mute) = ustate.mute {
                                                            if mute != prev.is_muted {
                                                                if Some(session) == my_session {
                                                                    msg = Some(format!("You were {} by {}.", if mute { "muted" } else { "unmuted" }, actor));
                                                                } else if ustate.actor == my_session {
                                                                    msg = Some(format!("You {} {}.", if mute { "muted" } else { "unmuted" }, target_name));
                                                                } else {
                                                                    msg = Some(format!("{} was {} by {}.", target_name, if mute { "muted" } else { "unmuted" }, actor));
                                                                }
                                                            }
                                                        }
                                                        if let Some(deaf) = ustate.deaf {
                                                            if deaf != prev.is_deafened {
                                                                if Some(session) == my_session {
                                                                    msg = Some(format!("You were {} by {}.", if deaf { "deafened" } else { "undeafened" }, actor));
                                                                } else if ustate.actor == my_session {
                                                                    msg = Some(format!("You {} {}.", if deaf { "deafened" } else { "undeafened" }, target_name));
                                                                } else {
                                                                    msg = Some(format!("{} was {} by {}.", target_name, if deaf { "deafened" } else { "undeafened" }, actor));
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Registration
                                                if msg.is_none() && prev.user_id.is_none() && ustate.user_id.is_some() {
                                                    if Some(session) == my_session {
                                                        msg = Some("You registered on the server.".to_string());
                                                    } else {
                                                        msg = Some(format!("{} registered on the server.", target_name));
                                                    }
                                                }

                                                // Recording
                                                if msg.is_none() {
                                                    if let Some(rec) = ustate.recording {
                                                        if rec != prev.is_recording {
                                                            if Some(session) == my_session {
                                                                msg = Some(if rec { "Recording started.".to_string() } else { "Recording stopped.".to_string() });
                                                            } else {
                                                                msg = Some(format!("{} is {} recording.", target_name, if rec { "now" } else { "no longer" }));
                                                            }
                                                        }
                                                    }
                                                }

                                                // Priority Speaker
                                                if msg.is_none() {
                                                    if let Some(prio) = ustate.priority_speaker {
                                                        if prio != prev.is_priority_speaker && prio {
                                                            if Some(session) == my_session {
                                                                msg = Some("You are now priority speaker.".to_string());
                                                            } else {
                                                                msg = Some(format!("{} is now priority speaker.", target_name));
                                                            }
                                                        }
                                                    }
                                                }

                                                // Comment
                                                if msg.is_none() && ustate.comment.is_some() && ustate.comment.as_deref() != prev.comment.as_deref() {
                                                    if Some(session) == my_session {
                                                        msg = Some("You changed comment.".to_string());
                                                    } else {
                                                        msg = Some(format!("{} changed comment.", target_name));
                                                    }
                                                }

                                                // Avatar
                                                if msg.is_none() && (ustate.texture.is_some() || ustate.texture_hash.is_some()) {
                                                    if Some(session) == my_session {
                                                        msg = Some("You changed avatar.".to_string());
                                                    } else {
                                                        msg = Some(format!("{} changed avatar.", target_name));
                                                    }
                                                }
                                            } else if !target_name.is_empty() {
                                                // New user connected
                                                if Some(session) != my_session {
                                                    msg = Some(format!("{} connected.", target_name));
                                                }
                                            }
                                        }

                                        state.update_user(ustate.clone());
                                        (msg, state.users_list())
                                    };
                                    if let Some(msg) = user_event_msg {
                                        let timestamp = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_millis() as u64;
                                        let chat = ChatMessage {
                                            sender_session: 0,
                                            sender_name: "System".to_string(),
                                            channel_id: None,
                                            recipient_session: None,
                                            html_body: msg,
                                            timestamp,
                                        };
                                        handler_arc.on_chat_message(chat);
                                    }
                                    handler_arc.on_users_updated(users);

                                    // If comment or texture was not sent inline but hash was provided, request the full blob
                                    let mut req_comments = Vec::new();
                                    let mut req_textures = Vec::new();
                                    if ustate.comment.is_none() {
                                        if let (Some(sess), Some(ref hash)) = (ustate.session, &ustate.comment_hash) {
                                            if !hash.is_empty() {
                                                req_comments.push(sess);
                                            }
                                        }
                                    }
                                    if ustate.texture.is_none() {
                                        if let (Some(sess), Some(ref hash)) = (ustate.session, &ustate.texture_hash) {
                                            if !hash.is_empty() {
                                                req_textures.push(sess);
                                            }
                                        }
                                    }
                                    if !req_comments.is_empty() || !req_textures.is_empty() {
                                        let req = proto::RequestBlob {
                                            session_texture: req_textures,
                                            session_comment: req_comments,
                                            channel_description: vec![],
                                        };
                                        let _ = cmd_tx_blob.try_send(OutgoingCommand::Proto(TYPE_REQUEST_BLOB, req.encode_to_vec()));
                                    }
                                }
                            }
                            TYPE_USER_REMOVE => {
                                if let Ok(uremove) = proto::UserRemove::decode(&packet.payload[..]) {
                                    let (removed_user_name, is_self, is_actor_self) = {
                                        let state = state_arc.read().unwrap();
                                        let name = state.users.get(&uremove.session).map(|u| u.name.clone()).unwrap_or_else(|| "User".to_string());
                                        let is_me = state.my_session == Some(uremove.session);
                                        let is_actor_me = uremove.actor.is_some() && state.my_session == uremove.actor;
                                        (name, is_me, is_actor_me)
                                    };
                                    let actor_name = if let Some(actor_sess) = uremove.actor {
                                        let state = state_arc.read().unwrap();
                                        state.users.get(&actor_sess).map(|u| u.name.clone())
                                    } else {
                                        None
                                    };
                                    let reason_text = uremove.reason.as_deref().unwrap_or("").trim();
                                    let reason_suffix = if !reason_text.is_empty() {
                                        format!(": {}", reason_text)
                                    } else {
                                        ".".to_string()
                                    };

                                    let is_ban = uremove.ban.unwrap_or(false);
                                    let remove_msg = if is_ban {
                                        if is_self {
                                            if let Some(actor) = actor_name {
                                                format!("You were banned by {}{}", actor, reason_suffix)
                                            } else {
                                                format!("You were banned from the server{}", reason_suffix)
                                            }
                                        } else if is_actor_self {
                                            format!("You banned {}{}", removed_user_name, reason_suffix)
                                        } else {
                                            if let Some(actor) = actor_name {
                                                format!("{} was banned by {}{}", removed_user_name, actor, reason_suffix)
                                            } else {
                                                format!("{} was banned from the server{}", removed_user_name, reason_suffix)
                                            }
                                        }
                                    } else if let Some(actor) = actor_name {
                                        if uremove.actor != Some(uremove.session) {
                                            if is_self {
                                                format!("You were kicked by {}{}", actor, reason_suffix)
                                            } else if is_actor_self {
                                                format!("You kicked {}{}", removed_user_name, reason_suffix)
                                            } else {
                                                format!("{} was kicked by {}{}", removed_user_name, actor, reason_suffix)
                                            }
                                        } else {
                                            if is_self {
                                                "You disconnected.".to_string()
                                            } else {
                                                format!("{} disconnected.", removed_user_name)
                                            }
                                        }
                                    } else {
                                        if is_self {
                                            "You disconnected.".to_string()
                                        } else {
                                            format!("{} disconnected.", removed_user_name)
                                        }
                                    };

                                    let timestamp = SystemTime::now()
                                        .duration_since(UNIX_EPOCH)
                                        .unwrap_or_default()
                                        .as_millis() as u64;
                                    let chat = ChatMessage {
                                        sender_session: 0,
                                        sender_name: "System".to_string(),
                                        channel_id: None,
                                        recipient_session: None,
                                        html_body: remove_msg,
                                        timestamp,
                                    };
                                    handler_arc.on_chat_message(chat);

                                    let users = {
                                        let mut state = state_arc.write().unwrap();
                                        state.remove_user(uremove.session);
                                        state.users_list()
                                    };
                                    handler_arc.on_users_updated(users);
                                }
                            }
                            TYPE_TEXT_MESSAGE => {
                                if let Ok(tmsg) = proto::TextMessage::decode(&packet.payload[..]) {
                                    let sender_session = tmsg.actor.unwrap_or(0);
                                    let sender_name = {
                                        let state = state_arc.read().unwrap();
                                        state.users.get(&sender_session)
                                            .map(|u| u.name.clone())
                                            .unwrap_or_else(|| "Server".to_string())
                                    };
                                    let channel_id = tmsg.channel_id.first().copied();
                                    let recipient_session = tmsg.session.first().copied();
                                    let timestamp = SystemTime::now()
                                        .duration_since(UNIX_EPOCH)
                                        .unwrap_or_default()
                                        .as_millis() as u64;

                                    let chat = ChatMessage {
                                        sender_session,
                                        sender_name,
                                        channel_id,
                                        recipient_session,
                                        html_body: tmsg.message,
                                        timestamp,
                                    };
                                    handler_arc.on_chat_message(chat);
                                }
                            }
                            TYPE_VERSION => {
                                if let Ok(ver) = proto::Version::decode(&packet.payload[..]) {
                                    let info = {
                                        let mut state = state_arc.write().unwrap();
                                        if let Some(rel) = ver.release {
                                            state.server_info.server_version = rel;
                                        } else if let Some(v1) = ver.version_v1 {
                                            state.server_info.server_version = format!("{}.{}.{}", (v1 >> 16) & 0xFF, (v1 >> 8) & 0xFF, v1 & 0xFF);
                                        }
                                        if let Some(os) = ver.os {
                                            state.server_info.server_os = os;
                                        }
                                        if let Some(os_ver) = ver.os_version {
                                            state.server_info.server_os_version = os_ver;
                                        }
                                        state.server_info.clone()
                                    };
                                    handler_arc.on_server_connection_info_updated(info);
                                }
                            }
                            TYPE_SERVER_CONFIG => {
                                if let Ok(cfg) = proto::ServerConfig::decode(&packet.payload[..]) {
                                    let (info, new_welcome) = {
                                        let mut state = state_arc.write().unwrap();
                                        if let Some(max_band) = cfg.max_bandwidth {
                                            state.server_info.max_bandwidth_kbps = max_band / 1000;
                                        }
                                        let new_welcome = if let Some(ref welcome) = cfg.welcome_text {
                                            let trimmed = welcome.trim();
                                            if !trimmed.is_empty() && trimmed != state.server_info.welcome_text.trim() {
                                                state.server_info.welcome_text = welcome.clone();
                                                Some(welcome.clone())
                                            } else {
                                                None
                                            }
                                        } else {
                                            None
                                        };
                                        if let Some(max_users) = cfg.max_users {
                                            state.server_info.max_users = max_users;
                                        }
                                        (state.server_info.clone(), new_welcome)
                                    };
                                    handler_arc.on_server_connection_info_updated(info);

                                    if let Some(welcome) = new_welcome {
                                        let timestamp = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_millis() as u64;
                                        let chat = ChatMessage {
                                            sender_session: 0,
                                            sender_name: "Server".to_string(),
                                            channel_id: None,
                                            recipient_session: None,
                                            html_body: welcome,
                                            timestamp,
                                        };
                                        handler_arc.on_chat_message(chat);
                                    }
                                }
                            }
                            TYPE_PING => {
                                if let Ok(ping) = proto::Ping::decode(&packet.payload[..]) {
                                    let tcp_ms = if let Some(sent_ts) = ping.timestamp {
                                        let now = SystemTime::now()
                                            .duration_since(UNIX_EPOCH)
                                            .unwrap_or_default()
                                            .as_micros() as u64;
                                        if now >= sent_ts {
                                            ((now - sent_ts) as f32) / 1000.0
                                        } else {
                                            ping.tcp_ping_avg.unwrap_or(0.0)
                                        }
                                    } else {
                                        ping.tcp_ping_avg.unwrap_or(0.0)
                                    };
                                    let udp_ms = ping.udp_ping_avg.unwrap_or(0.0);
                                    let using_udp = last_udp_ping_arc.read().unwrap().elapsed() < Duration::from_secs(15);
                                    handler_arc.on_ping_updated(tcp_ms, udp_ms, !using_udp);

                                    let info = {
                                        let mut state = state_arc.write().unwrap();
                                        state.server_info.tcp_ping_ms = tcp_ms;
                                        state.server_info.udp_ping_ms = udp_ms;
                                        state.server_info.using_udp_tunnel = !using_udp;
                                        if let Some(good) = ping.good { state.server_info.good_packets = good; }
                                        if let Some(late) = ping.late { state.server_info.late_packets = late; }
                                        if let Some(lost) = ping.lost { state.server_info.lost_packets = lost; }
                                        if let Some(resync) = ping.resync { state.server_info.resync_packets = resync; }
                                        state.server_info.tcp_packets_sent = tcp_sent_arc.load(Ordering::Relaxed);
                                        state.server_info.udp_packets_sent = udp_sent_arc.load(Ordering::Relaxed);
                                        state.server_info.clone()
                                    };
                                    handler_arc.on_server_connection_info_updated(info);
                                }
                            }
                            TYPE_CRYPT_SETUP => {
                                if let Ok(setup) = proto::CryptSetup::decode(&packet.payload[..]) {
                                    if let (Some(key), Some(client_nonce), Some(server_nonce)) =
                                        (setup.key, setup.client_nonce, setup.server_nonce)
                                    {
                                        if key.len() == 16 && client_nonce.len() == 16 && server_nonce.len() == 16 {
                                            let crypt = CryptStateOCB2::new(&key, &client_nonce, &server_nonce);
                                            *crypt_arc.lock().unwrap() = Some(crypt);

                                            // Setup non-blocking UDP socket connected to Murmur server
                                            if let Ok(udp) = UdpSocket::bind("0.0.0.0:0").await {
                                                let target_addr = format!("{}:{}", host_for_udp, port);
                                                if udp.connect(&target_addr).await.is_ok() {
                                                    let udp_shared = Arc::new(udp);
                                                    *udp_socket_holder.write().unwrap() = Some(Arc::clone(&udp_shared));

                                                    // UDP Ping heartbeat task (sends UDP Ping every 5s)
                                                    let udp_ping_sock = Arc::clone(&udp_shared);
                                                    let crypt_ping = Arc::clone(&crypt_arc);
                                                    let udp_sent_ping = Arc::clone(&udp_sent_arc);
                                                    let mut udp_shutdown_rx = shutdown_rx.clone();

                                                    runner_arc.spawn(async move {
                                                        let mut interval = tokio::time::interval(Duration::from_secs(5));
                                                        loop {
                                                            tokio::select! {
                                                                _ = interval.tick() => {
                                                                    let ts = SystemTime::now()
                                                                        .duration_since(UNIX_EPOCH)
                                                                        .unwrap_or_default()
                                                                        .as_micros() as u64;
                                                                    let ping_bytes = encode_udp_ping(ts);
                                                                    let mut encrypted = vec![0u8; ping_bytes.len() + 4];
                                                                    let crypted = {
                                                                        if let Some(ref mut c) = *crypt_ping.lock().unwrap() {
                                                                            c.encrypt(&ping_bytes, &mut encrypted).ok()
                                                                        } else {
                                                                            None
                                                                        }
                                                                    };
                                                                    if let Some(len) = crypted {
                                                                        if udp_ping_sock.send(&encrypted[..len]).await.is_ok() {
                                                                            udp_sent_ping.fetch_add(1, Ordering::Relaxed);
                                                                        }
                                                                    }
                                                                }
                                                                _ = udp_shutdown_rx.changed() => {
                                                                    break;
                                                                }
                                                            }
                                                        }
                                                    });

                                                    // UDP Receive loop
                                                    let udp_recv_sock = Arc::clone(&udp_shared);
                                                    let crypt_recv = Arc::clone(&crypt_arc);
                                                    let last_ping_recv = Arc::clone(&last_udp_ping_arc);
                                                    let mixer_recv = Arc::clone(&mixer_arc);
                                                    let state_recv = Arc::clone(&state_arc);
                                                    let handler_recv = Arc::clone(&handler_arc);
                                                    let self_priority_recv = Arc::clone(&self_priority_for_udp);
                                                    let mut udp_recv_shutdown_rx = shutdown_rx.clone();

                                                    runner_arc.spawn(async move {
                                                        let mut buf = [0u8; 2048];
                                                        let mut plain = [0u8; 2048];
                                                        loop {
                                                            tokio::select! {
                                                                recv_res = udp_recv_sock.recv(&mut buf) => {
                                                                    let n = match recv_res {
                                                                        Ok(n) => n,
                                                                        Err(_) => break,
                                                                    };
                                                                    let decrypted = {
                                                                        if let Some(ref mut c) = *crypt_recv.lock().unwrap() {
                                                                            c.decrypt(&buf[..n], &mut plain).ok()
                                                                        } else {
                                                                            None
                                                                        }
                                                                    };
                                                                    if let Some(plain_len) = decrypted {
                                                                        let packet_data = &plain[..plain_len];
                                                                        if packet_data.is_empty() {
                                                                            continue;
                                                                        }
                                                                        let packet_type = (packet_data[0] >> 5) & 0x07;
                                                                        if packet_type == 1 {
                                                                            // UDP Ping reply
                                                                            if let Ok(reply) = decode_udp_ping_reply(packet_data) {
                                                                                *last_ping_recv.write().unwrap() = Instant::now();
                                                                                let now = SystemTime::now()
                                                                                    .duration_since(UNIX_EPOCH)
                                                                                    .unwrap_or_default()
                                                                                    .as_micros() as u64;
                                                                                let udp_ms = if now >= reply.timestamp {
                                                                                    ((now - reply.timestamp) as f32) / 1000.0
                                                                                } else {
                                                                                    0.0
                                                                                };
                                                                                handler_recv.on_ping_updated(0.0, udp_ms, false);
                                                                            }
                                                                        } else if packet_type == 4 {
                                                                            // Opus Voice packet over UDP
                                                                            if let Ok(voice_pkt) = decode_server_voice(packet_data) {
                                                                                let (volumes, priority_speakers) = {
                                                                                    let state = state_recv.read().unwrap();
                                                                                    let prio = state
                                                                                        .users
                                                                                        .values()
                                                                                        .filter(|u| u.is_priority_speaker)
                                                                                        .map(|u| u.session_id)
                                                                                        .collect::<HashSet<u32>>();
                                                                                    (state.user_volumes.clone(), prio)
                                                                                };
                                                                                let self_priority_talking = self_priority_recv.load(Ordering::Relaxed);
                                                                                let talking_change = {
                                                                                    if let Ok(mut mixer) = mixer_recv.lock() {
                                                                                        mixer.process_incoming_voice(voice_pkt, &volumes, &priority_speakers, self_priority_talking)
                                                                                    } else {
                                                                                        None
                                                                                    }
                                                                                };
                                                                                if let Some((sess, talking, talking_state)) = talking_change {
                                                                                    state_recv.write().unwrap().set_user_talking(sess, talking, talking_state);
                                                                                    handler_recv.on_user_talking_changed(sess, talking, talking_state);
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                                _ = udp_recv_shutdown_rx.changed() => {
                                                                    break;
                                                                }
                                                            }
                                                        }
                                                    });
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            TYPE_UDP_TUNNEL => {
                                // Raw voice packet tunneled through TCP
                                if let Ok(voice_pkt) = decode_server_voice(&packet.payload) {
                                    let (volumes, priority_speakers) = {
                                        let state = state_arc.read().unwrap();
                                        let prio = state
                                            .users
                                            .values()
                                            .filter(|u| u.is_priority_speaker)
                                            .map(|u| u.session_id)
                                            .collect::<HashSet<u32>>();
                                        (state.user_volumes.clone(), prio)
                                    };
                                    let self_priority_talking = self_priority_for_tcp.load(Ordering::Relaxed);
                                    let talking_change = {
                                        if let Ok(mut mixer) = mixer_arc.lock() {
                                            mixer.process_incoming_voice(voice_pkt, &volumes, &priority_speakers, self_priority_talking)
                                        } else {
                                            None
                                        }
                                    };
                                    if let Some((sess, talking, talking_state)) = talking_change {
                                        state_arc.write().unwrap().set_user_talking(sess, talking, talking_state);
                                        handler_arc.on_user_talking_changed(sess, talking, talking_state);
                                    }
                                }
                            }
                            TYPE_PERMISSION_DENIED => {
                                if let Ok(denied) = proto::PermissionDenied::decode(&packet.payload[..]) {
                                    let (ch_name, target_user_name, is_self) = {
                                        let state = state_arc.read().unwrap();
                                        let ch = denied.channel_id.and_then(|cid| state.channels.get(&cid).map(|c| c.name.clone()))
                                            .unwrap_or_else(|| {
                                                if let Some(cid) = denied.channel_id {
                                                    format!("Channel #{}", cid)
                                                } else {
                                                    "Root".to_string()
                                                }
                                            });
                                        let is_me = denied.session.is_none() || denied.session == state.my_session;
                                        let user = denied.session.and_then(|s| state.users.get(&s).map(|u| u.name.clone()))
                                            .unwrap_or_else(|| "User".to_string());
                                        (ch, user, is_me)
                                    };

                                    let perm_name = match denied.permission.unwrap_or(0) {
                                        0x1 => "Write",
                                        0x2 => "Traverse",
                                        0x4 => "Enter",
                                        0x8 => "Speak",
                                        0x10 => "Mute/Deafen",
                                        0x20 => "Move",
                                        0x40 => "Make channel",
                                        0x80 => "Link channel",
                                        0x100 => "Whisper",
                                        0x200 => "Text message",
                                        0x400 => "Temporary channel",
                                        0x800 => "Listen",
                                        _ => "requested",
                                    };

                                    let is_enter_perm = denied.permission == Some(0x4) || (denied.permission.unwrap_or(0) & 0x4 != 0);

                                    let msg = match denied.r#type {
                                        Some(1) | None if denied.permission.is_some() || denied.r#type == Some(1) => {
                                            if is_enter_perm {
                                                format!("Unable to Enter into {} - Adding the respective access (password) token might grant you access.", ch_name)
                                            } else if is_self {
                                                format!("You were denied {} privileges in {}.", perm_name, ch_name)
                                            } else {
                                                format!("{} was denied {} privileges in {}.", target_user_name, perm_name, ch_name)
                                            }
                                        }
                                        Some(2) => "Cannot modify SuperUser.".to_string(),
                                        Some(3) => "According to the server's configuration, the channel name is considered invalid.".to_string(),
                                        Some(4) => "Text message too long.".to_string(),
                                        Some(5) => "The flux capacitor was spelled wrong.".to_string(),
                                        Some(6) => "Operation not permitted in temporary channel.".to_string(),
                                        Some(7) => "Operation requires certificate.".to_string(),
                                        Some(8) => {
                                            if let Some(ref bad_name) = denied.name {
                                                format!("According to the server's configuration, the name '{}' is considered invalid.", bad_name)
                                            } else {
                                                "According to the server's configuration, the name is considered invalid.".to_string()
                                            }
                                        }
                                        Some(9) => "Channel is full.".to_string(),
                                        Some(10) => "Channel nesting limit reached.".to_string(),
                                        Some(11) => "Maximum channel count reached.".to_string(),
                                        Some(12) => "Amount of listener objects for this channel has been reached.".to_string(),
                                        Some(13) => "Amount of listener proxies for the user has been reached.".to_string(),
                                        _ => {
                                            if let Some(ref r) = denied.reason {
                                                r.clone()
                                            } else if is_enter_perm {
                                                format!("Unable to Enter into {} - Adding the respective access (password) token might grant you access.", ch_name)
                                            } else {
                                                "Permission denied.".to_string()
                                            }
                                        }
                                    };

                                    let formatted_msg = if msg.starts_with("Unable to") || msg.starts_with("You were denied") || msg.contains("was denied") || msg.starts_with("Denied:") {
                                        msg
                                    } else if let Some(ref r) = denied.reason {
                                        if !r.is_empty() && r != &msg {
                                            format!("Denied: {} ({})", msg, r)
                                        } else {
                                            format!("Denied: {}", msg)
                                        }
                                    } else {
                                        format!("Denied: {}", msg)
                                    };

                                    eprintln!("PermissionDenied from server: {}", formatted_msg);
                                    let timestamp = SystemTime::now()
                                        .duration_since(UNIX_EPOCH)
                                        .unwrap_or_default()
                                        .as_millis() as u64;
                                    let chat = ChatMessage {
                                        sender_session: 0,
                                        sender_name: "System".to_string(),
                                        channel_id: None,
                                        recipient_session: None,
                                        html_body: formatted_msg,
                                        timestamp,
                                    };
                                    handler_arc.on_chat_message(chat);
                                    let users = state_arc.read().unwrap().users_list();
                                    handler_arc.on_users_updated(users);

                                    // If permission denied was for a specific channel, mark it as locked
                                    if let Some(cid) = denied.channel_id {
                                        let mut updated = false;
                                        {
                                            let mut state = state_arc.write().unwrap();
                                            if let Some(ch) = state.channels.get_mut(&cid) {
                                                ch.is_enter_restricted = true;
                                                ch.can_enter = false;
                                                updated = true;
                                            }
                                        }
                                        if updated {
                                            let channels = state_arc.read().unwrap().channels_list();
                                            handler_arc.on_channels_updated(channels);
                                        }
                                    }
                                }
                            }
                            TYPE_PERMISSION_QUERY => {
                                if let Ok(pq) = proto::PermissionQuery::decode(&packet.payload[..]) {
                                    let mut trigger_channel_update = false;
                                    if let (Some(cid), Some(perms)) = (pq.channel_id, pq.permissions) {
                                        let can_enter = (perms & 0x4) != 0 || (perms & 0x1) != 0;
                                        let mut state = state_arc.write().unwrap();
                                        if let Some(ch) = state.channels.get_mut(&cid) {
                                            if !can_enter {
                                                ch.is_enter_restricted = true;
                                            }
                                            if ch.can_enter != can_enter {
                                                ch.can_enter = can_enter;
                                                trigger_channel_update = true;
                                            }
                                        }
                                    }
                                    if trigger_channel_update {
                                        let channels = state_arc.read().unwrap().channels_list();
                                        handler_arc.on_channels_updated(channels);
                                    }
                                }
                            }
                            TYPE_REJECT => {
                                if let Ok(reject) = proto::Reject::decode(&packet.payload[..]) {
                                    let reason_str = match reject.r#type {
                                        Some(1) => "Incompatible version.".to_string(),
                                        Some(2) => "Invalid username.".to_string(),
                                        Some(3) => "Wrong user password.".to_string(),
                                        Some(4) => "Wrong server password.".to_string(),
                                        Some(5) => "Username already in use.".to_string(),
                                        Some(6) => "Server is full.".to_string(),
                                        Some(7) => "A certificate is required to connect to this server.".to_string(),
                                        Some(8) => "Authenticator failed.".to_string(),
                                        Some(9) => "The server is currently not accepting new connections.".to_string(),
                                        _ => reject.reason.clone().unwrap_or_else(|| "Connection rejected.".to_string()),
                                    };
                                    let full_reason = if let Some(ref r) = reject.reason {
                                        if !r.is_empty() && r != &reason_str {
                                            format!("{} ({})", reason_str, r)
                                        } else {
                                            reason_str
                                        }
                                    } else {
                                        reason_str
                                    };
                                    eprintln!("Mumble connection rejected: {}", full_reason);
                                    let timestamp = SystemTime::now()
                                        .duration_since(UNIX_EPOCH)
                                        .unwrap_or_default()
                                        .as_millis() as u64;
                                    let chat = ChatMessage {
                                        sender_session: 0,
                                        sender_name: "System".to_string(),
                                        channel_id: None,
                                        recipient_session: None,
                                        html_body: format!("Connection rejected: {}", full_reason),
                                        timestamp,
                                    };
                                    handler_arc.on_chat_message(chat);
                                    state_arc.write().unwrap().connection_status = ConnectionStatus::Failed;
                                    handler_arc.on_connection_status_changed(ConnectionStatus::Failed);
                                    break;
                                }
                            }
                            TYPE_USER_LIST => {
                                if let Ok(ul) = proto::UserList::decode(&packet.payload[..]) {
                                    let users: Vec<RegisteredUser> = ul
                                        .users
                                        .into_iter()
                                        .map(|u| RegisteredUser {
                                            user_id: u.user_id,
                                            name: u.name.unwrap_or_default(),
                                            last_seen: u.last_seen,
                                            last_channel_id: u.last_channel,
                                        })
                                        .collect();
                                    {
                                        let mut state = state_arc.write().unwrap();
                                        state.registered_users = users.clone();
                                    }
                                    handler_arc.on_registered_users_updated(users);
                                }
                            }
                            TYPE_BAN_LIST => {
                                if let Ok(bl) = proto::BanList::decode(&packet.payload[..]) {
                                    let bans: Vec<BanEntryInfo> = bl
                                        .bans
                                        .into_iter()
                                        .map(|b| {
                                            let ip_str = decode_ban_ip(&b.address);
                                            let effective_mask = if b.mask >= 96
                                                && b.address.len() == 16
                                                && is_ipv4_mapped(&b.address)
                                            {
                                                b.mask - 96
                                            } else {
                                                b.mask
                                            };
                                            BanEntryInfo {
                                                ip: ip_str,
                                                mask: effective_mask,
                                                name: b.name.unwrap_or_default(),
                                                hash: b.hash.unwrap_or_default(),
                                                reason: b.reason.unwrap_or_default(),
                                                start: b.start.unwrap_or_default(),
                                                duration: b.duration.unwrap_or(0),
                                            }
                                        })
                                        .collect();
                                    {
                                        let mut state = state_arc.write().unwrap();
                                        state.ban_list = bans.clone();
                                    }
                                    handler_arc.on_ban_list_updated(bans);
                                }
                            }
                            TYPE_USER_STATS => {
                                if let Ok(us) = proto::UserStats::decode(&packet.payload[..]) {
                                    let session_id = us.session.unwrap_or(0);
                                    let user_name = state_arc
                                        .read()
                                        .unwrap()
                                        .users
                                        .get(&session_id)
                                        .map(|u| u.name.clone())
                                        .unwrap_or_else(|| format!("User #{}", session_id));

                                    let (ver_v, ver_rel, ver_os, ver_os_v) = if let Some(v) = us.version {
                                        let v_int = v.version_v1.unwrap_or(0);
                                        let v_str = if v_int > 0 {
                                            format!("{}.{}.{}", (v_int >> 16) & 0xff, (v_int >> 8) & 0xff, v_int & 0xff)
                                        } else if let Some(v2) = v.version_v2 {
                                            format!("{}.{}.{}", (v2 >> 48) & 0xffff, (v2 >> 32) & 0xffff, (v2 >> 16) & 0xffff)
                                        } else {
                                            String::new()
                                        };
                                        (v_str, v.release.unwrap_or_default(), v.os.unwrap_or_default(), v.os_version.unwrap_or_default())
                                    } else {
                                        (String::new(), String::new(), String::new(), String::new())
                                    };

                                    let ip_address = us.address.as_deref().map(decode_ban_ip).unwrap_or_default();

                                    let cert_der = us.certificates.first().cloned();
                                    let cert_name = if cert_der.is_some() {
                                        "Swimble User".to_string()
                                    } else {
                                        "None".to_string()
                                    };
                                    let cert_details = if let Some(ref der) = cert_der {
                                        format!("Certificate ({} bytes DER)", der.len())
                                    } else {
                                        "No certificate".to_string()
                                    };

                                    let from_client = us.from_client.map(|s| PacketStats {
                                        good: s.good.unwrap_or(0),
                                        late: s.late.unwrap_or(0),
                                        lost: s.lost.unwrap_or(0),
                                        resync: s.resync.unwrap_or(0),
                                    }).unwrap_or_default();

                                    let from_server = us.from_server.map(|s| PacketStats {
                                        good: s.good.unwrap_or(0),
                                        late: s.late.unwrap_or(0),
                                        lost: s.lost.unwrap_or(0),
                                        resync: s.resync.unwrap_or(0),
                                    }).unwrap_or_default();

                                    let stats_info = UserStatsInfo {
                                        session_id,
                                        user_name,
                                        version_v: ver_v,
                                        version_os: ver_os,
                                        version_os_version: ver_os_v,
                                        version_release: ver_rel,
                                        ip_address,
                                        certificate_name: cert_name,
                                        certificate_details: cert_details,
                                        certificate_der: cert_der,
                                        strong_certificate: us.strong_certificate.unwrap_or(false),
                                        opus_supported: us.opus.unwrap_or(false),
                                        tcp_ping_avg: us.tcp_ping_avg.unwrap_or(0.0),
                                        tcp_ping_var: us.tcp_ping_var.unwrap_or(0.0),
                                        udp_ping_avg: us.udp_ping_avg.unwrap_or(0.0),
                                        udp_ping_var: us.udp_ping_var.unwrap_or(0.0),
                                        tcp_packets: us.tcp_packets.unwrap_or(0),
                                        udp_packets: us.udp_packets.unwrap_or(0),
                                        from_client,
                                        from_server,
                                        bandwidth: us.bandwidth.unwrap_or(0),
                                        onlinesecs: us.onlinesecs.unwrap_or(0),
                                        idlesecs: us.idlesecs.unwrap_or(0),
                                    };

                                    handler_arc.on_user_stats_received(stats_info);
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }

            let _ = writer_handle.await;
            let was_synced = {
                let mut state = state_arc.write().unwrap();
                let synced = state.is_synced;
                state.is_synced = false;
                state.connection_status = ConnectionStatus::Disconnected;
                synced
            };
            if was_synced {
                let timestamp = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64;
                let chat = ChatMessage {
                    sender_session: 0,
                    sender_name: "System".to_string(),
                    channel_id: None,
                    recipient_session: None,
                    html_body: "Server connection closed.".to_string(),
                    timestamp,
                };
                handler_arc.on_chat_message(chat);
            }
            handler_arc.on_connection_status_changed(ConnectionStatus::Disconnected);
        });
    }

    pub fn disconnect(&self) {
        self.self_priority_transmitting.store(false, Ordering::Relaxed);
        if let Some(tx) = self.shutdown_tx.write().unwrap().take() {
            let _ = tx.send(true);
        }
        if let Some(cmd_tx) = self.command_tx.write().unwrap().take() {
            let _ = cmd_tx.try_send(OutgoingCommand::Disconnect);
        }
        let _ = self.voice_tx.write().unwrap().take();
        *self.crypt_state.lock().unwrap() = None;
        {
            let mut state = self.state.write().unwrap();
            state.connection_status = ConnectionStatus::Disconnected;
        }
        self.handler
            .on_connection_status_changed(ConnectionStatus::Disconnected);
    }

    pub fn join_channel(&self, channel_id: u32) {
        let msg = proto::UserState {
            channel_id: Some(channel_id),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &msg);
    }

    pub fn send_chat_message(&self, channel_id: u32, message: String) {
        let msg = proto::TextMessage {
            channel_id: vec![channel_id],
            message,
            ..Default::default()
        };
        self.send_proto(TYPE_TEXT_MESSAGE, &msg);
    }

    pub fn set_self_mute(&self, muted: bool) {
        if let Ok(mut state) = self.state.write() {
            if let Some(sid) = state.my_session {
                if let Some(user) = state.users.get_mut(&sid) {
                    user.is_self_muted = muted;
                }
            }
        }
        let msg = proto::UserState {
            self_mute: Some(muted),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &msg);
    }

    pub fn set_self_deaf(&self, deafened: bool) {
        if let Ok(mut state) = self.state.write() {
            if let Some(sid) = state.my_session {
                if let Some(user) = state.users.get_mut(&sid) {
                    user.is_self_deafened = deafened;
                    if deafened {
                        user.is_self_muted = true;
                    }
                }
            }
        }
        let msg = proto::UserState {
            self_deaf: Some(deafened),
            self_mute: if deafened { Some(true) } else { None },
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &msg);
    }

    pub fn set_user_local_volume(&self, session_id: u32, volume_multiplier: f32) {
        let mut state = self.state.write().unwrap();
        state.user_volumes.insert(session_id, volume_multiplier);
    }

    pub fn push_mic_pcm(&self, samples: Vec<f32>, target: Option<u8>) {
        let is_priority = {
            let state = self.state.read().unwrap();
            state
                .my_session
                .and_then(|sid| state.users.get(&sid))
                .map(|u| u.is_priority_speaker)
                .unwrap_or(false)
        };
        self.self_priority_transmitting.store(is_priority, Ordering::Relaxed);

        let effective_target = target.unwrap_or_else(|| *self.active_voice_target_id.read().unwrap());
        let packets = {
            if let Ok(mut mixer) = self.audio_mixer.lock() {
                mixer.push_mic_pcm(&samples, effective_target)
            } else {
                vec![]
            }
        };

        for pkt in packets {
            let encoded = encode_client_voice(&pkt);
            if let Ok(guard) = self.voice_tx.read() {
                if let Some(ref tx) = *guard {
                    let _ = tx.try_send(encoded);
                }
            }
        }
    }

    pub fn finish_mic_stream(&self, target: Option<u8>) {
        self.self_priority_transmitting.store(false, Ordering::Relaxed);

        let effective_target = target.unwrap_or_else(|| *self.active_voice_target_id.read().unwrap());
        let maybe_pkt = {
            if let Ok(mut mixer) = self.audio_mixer.lock() {
                mixer.finish_mic_stream(effective_target)
            } else {
                None
            }
        };

        if let Some(pkt) = maybe_pkt {
            let encoded = encode_client_voice(&pkt);
            if let Ok(guard) = self.voice_tx.read() {
                if let Some(ref tx) = *guard {
                    let _ = tx.try_send(encoded);
                }
            }
        }
    }

    pub fn set_voice_target(&self, config: VoiceTargetConfig) {
        let target = proto::voice_target::Target {
            session: config.sessions,
            channel_id: config.channel_id,
            group: config.group,
            links: Some(config.links),
            children: Some(config.children),
        };
        let vt = proto::VoiceTarget {
            id: Some(config.id),
            targets: vec![target],
        };
        self.send_proto(TYPE_VOICE_TARGET, &vt);
    }

    pub fn set_active_voice_target_id(&self, target_id: u8) {
        *self.active_voice_target_id.write().unwrap() = target_id;
    }

    pub fn get_active_voice_target_id(&self) -> u8 {
        *self.active_voice_target_id.read().unwrap()
    }

    pub fn get_server_connection_info(&self) -> ServerConnectionInfo {
        self.state.read().unwrap().server_info.clone()
    }

    pub fn create_channel(
        &self,
        parent_id: u32,
        name: String,
        description: String,
        position: i32,
        is_temporary: bool,
    ) {
        let cstate = proto::ChannelState {
            parent: Some(parent_id),
            name: Some(name),
            description: Some(description),
            position: Some(position),
            temporary: Some(is_temporary),
            ..Default::default()
        };
        self.send_proto(TYPE_CHANNEL_STATE, &cstate);
    }

    pub fn set_channel_description(&self, channel_id: u32, description: String) {
        let cstate = proto::ChannelState {
            channel_id: Some(channel_id),
            description: Some(description),
            ..Default::default()
        };
        self.send_proto(TYPE_CHANNEL_STATE, &cstate);
    }

    pub fn remove_channel(&self, channel_id: u32) {
        let cremove = proto::ChannelRemove { channel_id };
        self.send_proto(TYPE_CHANNEL_REMOVE, &cremove);
    }

    pub fn register_user(&self, session_id: Option<u32>) {
        let target_session = session_id.or_else(|| self.state.read().unwrap().my_session);
        if let Some(session) = target_session {
            let ustate = proto::UserState {
                session: Some(session),
                user_id: Some(0),
                ..Default::default()
            };
            self.send_proto(TYPE_USER_STATE, &ustate);
        }
    }

    pub fn set_comment(&self, comment: String) {
        if let Some(session) = self.state.read().unwrap().my_session {
            let ustate = proto::UserState {
                session: Some(session),
                comment: Some(comment),
                ..Default::default()
            };
            self.send_proto(TYPE_USER_STATE, &ustate);
        }
    }

    pub fn set_avatar(&self, texture: Vec<u8>) {
        if let Some(session) = self.state.read().unwrap().my_session {
            let ustate = proto::UserState {
                session: Some(session),
                texture: Some(texture),
                ..Default::default()
            };
            self.send_proto(TYPE_USER_STATE, &ustate);
        }
    }

    pub fn request_blob(
        &self,
        session_textures: Vec<u32>,
        session_comments: Vec<u32>,
        channel_descriptions: Vec<u32>,
    ) {
        let req = proto::RequestBlob {
            session_texture: session_textures,
            session_comment: session_comments,
            channel_description: channel_descriptions,
        };
        self.send_proto(TYPE_REQUEST_BLOB, &req);
    }

    pub fn remove_avatar(&self) {
        if let Some(session) = self.state.read().unwrap().my_session {
            let ustate = proto::UserState {
                session: Some(session),
                texture: Some(vec![]),
                ..Default::default()
            };
            self.send_proto(TYPE_USER_STATE, &ustate);
        }
    }

    pub fn set_recording_state(&self, recording: bool) {
        if let Some(session) = self.state.read().unwrap().my_session {
            let ustate = proto::UserState {
                session: Some(session),
                recording: Some(recording),
                ..Default::default()
            };
            self.send_proto(TYPE_USER_STATE, &ustate);
        }
    }

    pub fn send_user_message(&self, session_id: u32, message: String) {
        let msg = proto::TextMessage {
            session: vec![session_id],
            message,
            ..Default::default()
        };
        self.send_proto(TYPE_TEXT_MESSAGE, &msg);
    }

    pub fn set_user_priority_speaker(&self, session_id: u32, priority: bool) {
        let is_self = self.state.read().unwrap().my_session == Some(session_id);
        let ustate = proto::UserState {
            session: if is_self { None } else { Some(session_id) },
            priority_speaker: Some(priority),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &ustate);
    }

    pub fn set_user_server_mute_deaf(&self, session_id: u32, mute: bool, deaf: bool) {
        let ustate = proto::UserState {
            session: Some(session_id),
            mute: Some(mute),
            deaf: Some(deaf),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &ustate);
    }

    pub fn move_user(&self, session_id: u32, channel_id: u32) {
        let ustate = proto::UserState {
            session: Some(session_id),
            channel_id: Some(channel_id),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATE, &ustate);
    }

    pub fn kick_user(&self, session_id: u32, reason: Option<String>) {
        let uremove = proto::UserRemove {
            session: session_id,
            reason,
            ban: Some(false),
            actor: self.state.read().unwrap().my_session,
            ..Default::default()
        };
        self.send_proto(TYPE_USER_REMOVE, &uremove);
    }

    pub fn ban_user(&self, session_id: u32, reason: Option<String>) {
        let uremove = proto::UserRemove {
            session: session_id,
            reason,
            ban: Some(true),
            actor: self.state.read().unwrap().my_session,
            ..Default::default()
        };
        self.send_proto(TYPE_USER_REMOVE, &uremove);
    }

    pub fn pull_speaker_pcm(&self, frame_count: u32) -> Vec<f32> {
        let mut out = vec![0.0f32; frame_count as usize];
        if let Ok(mut consumer) = self.speaker_consumer.lock() {
            for sample in out.iter_mut() {
                if let Ok(s) = consumer.pop() {
                    *sample = s;
                } else {
                    break;
                }
            }
        }
        out
    }

    pub fn get_channels(&self) -> Vec<ChannelInfo> {
        self.state.read().unwrap().channels_list()
    }

    pub fn get_users(&self) -> Vec<UserInfo> {
        self.state.read().unwrap().users_list()
    }

    pub fn get_connection_status(&self) -> ConnectionStatus {
        self.state.read().unwrap().connection_status
    }

    pub fn get_my_session(&self) -> Option<u32> {
        self.state.read().unwrap().my_session
    }

    pub fn set_tokens(&self, tokens: Vec<String>) {
        *self.tokens.write().unwrap() = tokens.clone();
        let auth = proto::Authenticate {
            tokens,
            ..Default::default()
        };
        self.send_proto(TYPE_AUTHENTICATE, &auth);
    }

    pub fn get_tokens(&self) -> Vec<String> {
        self.tokens.read().unwrap().clone()
    }

    pub fn request_registered_users(&self) {
        let ul = proto::UserList {
            users: vec![],
        };
        self.send_proto(TYPE_USER_LIST, &ul);
    }

    pub fn remove_registered_user(&self, user_id: u32) {
        let ul = proto::UserList {
            users: vec![proto::user_list::User {
                user_id,
                name: None,
                last_seen: None,
                last_channel: None,
            }],
        };
        self.send_proto(TYPE_USER_LIST, &ul);
        self.request_registered_users();
    }

    pub fn rename_registered_user(&self, user_id: u32, new_name: String) {
        let ul = proto::UserList {
            users: vec![proto::user_list::User {
                user_id,
                name: Some(new_name),
                last_seen: None,
                last_channel: None,
            }],
        };
        self.send_proto(TYPE_USER_LIST, &ul);
        self.request_registered_users();
    }

    pub fn request_ban_list(&self) {
        let bl = proto::BanList {
            bans: vec![],
            query: Some(true),
        };
        self.send_proto(TYPE_BAN_LIST, &bl);
    }

    pub fn set_ban_list(&self, bans: Vec<BanEntryInfo>) {
        let proto_bans: Vec<proto::ban_list::BanEntry> = bans
            .iter()
            .map(|b| {
                let (addr_bytes, proto_mask) = encode_ban_ip(&b.ip, b.mask);
                proto::ban_list::BanEntry {
                    address: addr_bytes,
                    mask: proto_mask,
                    name: if b.name.is_empty() { None } else { Some(b.name.clone()) },
                    hash: if b.hash.is_empty() { None } else { Some(b.hash.clone()) },
                    reason: if b.reason.is_empty() { None } else { Some(b.reason.clone()) },
                    start: if b.start.is_empty() { None } else { Some(b.start.clone()) },
                    duration: Some(b.duration),
                }
            })
            .collect();

        let bl = proto::BanList {
            bans: proto_bans,
            query: Some(false),
        };
        self.send_proto(TYPE_BAN_LIST, &bl);

        {
            let mut state = self.state.write().unwrap();
            state.ban_list = bans.clone();
        }
        self.handler.on_ban_list_updated(bans);
    }

    pub fn add_ban(&self, ip: String, mask: u32, reason: String, duration_seconds: u32) {
        let mut bans = self.state.read().unwrap().ban_list.clone();
        bans.push(BanEntryInfo {
            ip,
            mask,
            name: String::new(),
            hash: String::new(),
            reason,
            start: String::new(),
            duration: duration_seconds,
        });
        self.set_ban_list(bans);
    }

    pub fn remove_ban(&self, ip: String, mask: u32) {
        let mut bans = self.state.read().unwrap().ban_list.clone();
        bans.retain(|b| !(b.ip == ip && b.mask == mask));
        self.set_ban_list(bans);
    }

    pub fn get_registered_users(&self) -> Vec<RegisteredUser> {
        self.state.read().unwrap().registered_users.clone()
    }

    pub fn get_ban_list(&self) -> Vec<BanEntryInfo> {
        self.state.read().unwrap().ban_list.clone()
    }

    pub fn request_user_stats(&self, session_id: u32, stats_only: bool) {
        let msg = proto::UserStats {
            session: Some(session_id),
            stats_only: Some(stats_only),
            ..Default::default()
        };
        self.send_proto(TYPE_USER_STATS, &msg);
    }
}

impl MumbleClient {
    fn send_proto<M: Message>(&self, type_id: u16, msg: &M) {
        let payload = msg.encode_to_vec();
        if let Ok(guard) = self.command_tx.read() {
            if let Some(ref tx) = *guard {
                let _ = tx.try_send(OutgoingCommand::Proto(type_id, payload));
            }
        }
    }
}

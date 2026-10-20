use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::Notify;

use mumble_core::{
    generate_client_identity, BanEntryInfo, ChannelInfo, ChatMessage, ConnectionStatus,
    MumbleClient, MumbleEventHandler, RegisteredUser, ServerConnectionInfo, TalkingState, UserInfo,
    UserStatsInfo,
};

#[derive(Default)]
struct TestHandlerInner {
    connection_statuses: Vec<ConnectionStatus>,
    acl: Option<mumble_core::ChannelAcl>,
    channels: Vec<ChannelInfo>,
    users: Vec<UserInfo>,
    chat_messages: Vec<ChatMessage>,
}

struct TestHandler {
    inner: Arc<Mutex<TestHandlerInner>>,
    connected_notify: Arc<Notify>,
    #[allow(dead_code)]
    chat_notify: Arc<Notify>,
    user_update_notify: Arc<Notify>,
}

impl TestHandler {
    fn new(
        connected_notify: Arc<Notify>,
        chat_notify: Arc<Notify>,
        user_update_notify: Arc<Notify>,
    ) -> Self {
        Self {
            inner: Arc::new(Mutex::new(TestHandlerInner::default())),
            connected_notify,
            chat_notify,
            user_update_notify,
        }
    }
}

impl MumbleEventHandler for TestHandler {
    fn on_server_identity_challenge(&self, challenge: mumble_core::ServerIdentityChallenge) {
        panic!("Unexpected certificate challenge after explicit test pin: {challenge:?}");
    }
    fn on_channel_acl_received(&self, acl: mumble_core::ChannelAcl) {
        self.inner.lock().unwrap().acl = Some(acl);
    }

    fn on_connection_status_changed(&self, status: ConnectionStatus) {
        println!("TestHandler: connection status -> {:?}", status);
        self.inner.lock().unwrap().connection_statuses.push(status);
        if status == ConnectionStatus::Connected {
            self.connected_notify.notify_waiters();
        }
    }

    fn on_channels_updated(&self, channels: Vec<ChannelInfo>) {
        println!("TestHandler: channels updated (count: {})", channels.len());
        self.inner.lock().unwrap().channels = channels;
    }

    fn on_users_updated(&self, users: Vec<UserInfo>) {
        println!("TestHandler: users updated (count: {})", users.len());
        self.inner.lock().unwrap().users = users;
        self.user_update_notify.notify_waiters();
    }

    fn on_user_talking_changed(
        &self,
        session_id: u32,
        is_talking: bool,
        talking_state: TalkingState,
    ) {
        println!(
            "TestHandler: user {} talking: {} ({:?})",
            session_id, is_talking, talking_state
        );
    }

    fn on_chat_message(&self, message: ChatMessage) {
        println!(
            "TestHandler: chat message from {}: {}",
            message.sender_name, message.html_body
        );
        self.inner.lock().unwrap().chat_messages.push(message);
        self.chat_notify.notify_waiters();
    }

    fn on_ping_updated(&self, tcp_ms: f32, udp_ms: f32, using_udp_tunnel: bool) {
        println!(
            "TestHandler: ping updated: tcp={:.2}ms, udp={:.2}ms, tunnel={}",
            tcp_ms, udp_ms, using_udp_tunnel
        );
    }

    fn on_server_connection_info_updated(&self, info: ServerConnectionInfo) {
        println!("TestHandler: server info updated: {:?}", info);
    }

    fn on_registered_users_updated(&self, users: Vec<RegisteredUser>) {
        println!(
            "TestHandler: registered users updated (count: {})",
            users.len()
        );
    }

    fn on_ban_list_updated(&self, bans: Vec<BanEntryInfo>) {
        println!("TestHandler: ban list updated (count: {})", bans.len());
    }

    fn on_user_stats_received(&self, stats: UserStatsInfo) {
        println!("TestHandler: user stats received: {:?}", stats);
    }
}

#[tokio::test]
async fn test_murmur_live_integration() {
    let test_name = format!("SwimbleTest{}", std::process::id());
    let connected_notify = Arc::new(Notify::new());
    let chat_notify = Arc::new(Notify::new());
    let user_update_notify = Arc::new(Notify::new());

    let handler = TestHandler::new(
        Arc::clone(&connected_notify),
        Arc::clone(&chat_notify),
        Arc::clone(&user_update_notify),
    );

    let client = MumbleClient::new(Box::new(handler));

    // 1. Generate client identity certificate using rcgen
    println!("==> Generating client identity certificate...");
    let identity = generate_client_identity(test_name.clone());
    assert!(
        !identity.cert_pem.is_empty(),
        "Certificate PEM should not be empty"
    );
    assert!(!identity.key_pem.is_empty(), "Key PEM should not be empty");

    // The fixture intentionally uses a self-signed certificate. First prove
    // strict verification rejects it, then explicitly approve only that leaf.
    let failure = Arc::new(Mutex::new(None));
    let strict = mumble_core::connection::connect_tls(
        "127.0.0.1",
        64738,
        None,
        None,
        "127.0.0.1",
        64738,
        None,
        Arc::clone(&failure),
    )
    .await;
    assert!(
        strict.is_err(),
        "Fixture must be rejected without explicit trust"
    );
    let challenge = failure
        .lock()
        .unwrap()
        .take()
        .expect("Certificate challenge");
    let changed = mumble_core::connection::connect_tls(
        "127.0.0.1",
        64738,
        None,
        None,
        "127.0.0.1",
        64738,
        Some("00".into()),
        Arc::clone(&failure),
    )
    .await;
    assert!(
        changed.is_err(),
        "A different pinned certificate must be rejected"
    );

    // 2. Connect to local Murmur server
    println!("==> Connecting to Murmur on 127.0.0.1:64738...");
    client.connect(
        "127.0.0.1".to_string(),
        64738,
        test_name.clone(),
        None,
        Some(identity.cert_pem),
        Some(identity.key_pem),
        Some(challenge.fingerprint),
    );

    // 3. Wait for ServerSync (ConnectionStatus::Connected)
    let connected =
        tokio::time::timeout(Duration::from_secs(10), connected_notify.notified()).await;
    assert!(
        connected.is_ok(),
        "Timed out waiting for ServerSync / ConnectionStatus::Connected"
    );

    // Assert connection status
    assert_eq!(client.get_connection_status(), ConnectionStatus::Connected);
    let my_session = client
        .get_my_session()
        .expect("My session should be set on ServerSync");
    println!("==> Connected successfully! My session ID: {}", my_session);

    // 4. Assert that the Root channel and AntigravityTester user exist in state tree
    let channels = client.get_channels();
    println!("==> Discovered channels: {:?}", channels);
    client.request_channel_permissions(0);
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(
        client
            .get_channels()
            .iter()
            .find(|c| c.id == 0)
            .unwrap()
            .permissions
            .is_some(),
        "Murmur must return effective permissions"
    );
    let root_channel = channels.iter().find(|c| c.id == 0);
    assert!(root_channel.is_some(), "Root channel (id 0) must exist");
    assert_eq!(
        root_channel.unwrap().name,
        "Root",
        "Root channel name must be 'Root'"
    );

    let users = client.get_users();
    println!("==> Discovered users: {:?}", users);
    let me = users.iter().find(|u| u.name == test_name);
    assert!(
        me.is_some(),
        "'AntigravityTester' user must exist in state tree"
    );
    assert_eq!(me.unwrap().session_id, my_session);
    assert_eq!(
        me.unwrap().channel_id,
        0,
        "User should start in Root channel (id 0)"
    );

    // 5. Send a channel chat message
    println!("==> Sending channel chat message...");
    client.send_chat_message(0, "Hello Murmur from Antigravity test!".to_string());
    // Give brief time for the message packet to be processed by Murmur
    tokio::time::sleep(Duration::from_millis(100)).await;

    // 6. Toggle self-mute and wait for user state update
    println!("==> Toggling self-mute to true...");
    client.set_self_mute(true);
    let mute_reflected = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(user) = client
                .get_users()
                .iter()
                .find(|u| u.session_id == my_session)
            {
                if user.is_self_muted {
                    return;
                }
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await;
    assert!(
        mute_reflected.is_ok(),
        "Timed out waiting for self-mute to reflect in user state"
    );
    println!("==> Self-mute successfully updated and verified!");

    // 7. Disconnect cleanly
    println!("==> Disconnecting cleanly...");
    client.disconnect();
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(
        client.get_connection_status(),
        ConnectionStatus::Disconnected
    );
    println!("==> Integration test passed cleanly!");
}

#[tokio::test]
async fn test_ping_mumble_server_udp_and_tcp() {
    // 1. Local Murmur supports standard UDP ping
    let local_ping = mumble_core::ping_mumble_server("127.0.0.1".into(), 64738, 2000).await;
    assert!(
        local_ping.is_ok(),
        "Local UDP ping to 127.0.0.1:64738 failed: {:?}",
        local_ping.err()
    );
    let info = local_ping.unwrap();
    println!(
        "Local ping info: latency={}ms, users={}/{}, version={}",
        info.latency_ms, info.current_users, info.max_users, info.version
    );
    assert!(info.latency_ms >= 0.0);
}

#[tokio::test]
#[ignore = "Optional external network check; local tests must not depend on a community server"]
async fn test_remote_ping_gameone() {
    let remote_ping =
        mumble_core::ping_mumble_server("mumble.gameone.dev".into(), 64738, 3000).await;
    println!("Remote ping result: {:?}", remote_ping);
    assert!(remote_ping.is_ok());
}

// Run against the disposable admin fixture documented in scripts/test_acl.sh.
#[tokio::test]
#[ignore = "Requires disposable admin fixture on 127.0.0.1:64739"]
async fn test_acl_admin_fixture() {
    let connected = Arc::new(Notify::new());
    let handler = TestHandler::new(
        Arc::clone(&connected),
        Arc::new(Notify::new()),
        Arc::new(Notify::new()),
    );
    let handler_state = Arc::clone(&handler.inner);
    let client = MumbleClient::new(Box::new(handler));
    let failure = Arc::new(Mutex::new(None));
    assert!(mumble_core::connection::connect_tls(
        "127.0.0.1",
        64739,
        None,
        None,
        "127.0.0.1",
        64739,
        None,
        Arc::clone(&failure)
    )
    .await
    .is_err());
    let fingerprint = failure.lock().unwrap().take().unwrap().fingerprint;
    client.connect(
        "127.0.0.1".into(),
        64739,
        "SuperUser".into(),
        Some("swimble-local-acl-fixture".into()),
        None,
        None,
        Some(fingerprint.clone()),
    );
    tokio::time::timeout(Duration::from_secs(5), connected.notified())
        .await
        .unwrap();
    let my_session = client.get_my_session().unwrap();
    // Round-trip channel ACLs on this disposable server.
    let channel_name = format!("Swimble ACL test {}", my_session);
    client.create_channel(
        0,
        channel_name.clone(),
        "Integration fixture".into(),
        0,
        false,
    );
    let channel_id = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if let Some(channel) = client
                .get_channels()
                .iter()
                .find(|c| c.name == channel_name)
            {
                break channel.id;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Fixture channel creation");
    client.request_channel_acl(channel_id);
    let acl = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if let Some(acl) = handler_state
                .lock()
                .unwrap()
                .acl
                .clone()
                .filter(|a| a.channel_id == channel_id)
            {
                break acl;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Murmur ACL query");
    let mut updated = acl;
    updated.entries.push(mumble_core::ChannelAclEntry {
        apply_here: true,
        apply_subs: false,
        inherited: false,
        user_id: None,
        group: Some("swimble-integration-fixture".into()),
        grant: 0x200,
        deny: 0,
    });
    handler_state.lock().unwrap().acl = None;
    client.set_channel_acl(updated);
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if handler_state.lock().unwrap().acl.as_ref().is_some_and(|a| {
                a.entries.iter().any(|e| {
                    e.group.as_deref() == Some("swimble-integration-fixture")
                        && e.grant & 0x200 != 0
                })
            }) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Murmur must apply and return the new ACL rule");
    // Apply a registered-user rule and verify the affected Swimble client's
    // server suppression state, then restore Speak permission while connected.
    let user_connected = Arc::new(Notify::new());
    let user_handler = TestHandler::new(
        Arc::clone(&user_connected),
        Arc::new(Notify::new()),
        Arc::new(Notify::new()),
    );
    let user = MumbleClient::new(Box::new(user_handler));
    let identity = generate_client_identity("AclUser".into());
    user.connect(
        "127.0.0.1".into(),
        64739,
        "AclUser".into(),
        None,
        Some(identity.cert_pem.clone()),
        Some(identity.key_pem.clone()),
        Some(fingerprint.clone()),
    );
    tokio::time::timeout(Duration::from_secs(5), user_connected.notified())
        .await
        .unwrap();
    let session = user.get_my_session().unwrap();
    user.register_user(None);
    let registered_id = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if let Some(id) = user
                .get_users()
                .iter()
                .find(|u| u.session_id == session)
                .and_then(|u| u.user_id)
            {
                break id;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Fixture user registration");
    let mut acl = handler_state.lock().unwrap().acl.clone().unwrap();
    acl.entries.push(mumble_core::ChannelAclEntry {
        apply_here: true,
        apply_subs: true,
        inherited: false,
        user_id: Some(registered_id),
        group: None,
        grant: 0,
        deny: 0x8,
    });
    // Respect Murmur's control-message leaky bucket, as a human editor does.
    tokio::time::sleep(Duration::from_secs(2)).await;
    handler_state.lock().unwrap().acl = None;
    client.set_channel_acl(acl.clone());
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if handler_state.lock().unwrap().acl.as_ref().is_some_and(|a| {
                a.entries
                    .iter()
                    .any(|e| e.user_id == Some(registered_id) && e.deny & 8 != 0)
            }) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .unwrap_or_else(|_| {
        panic!(
            "Murmur must retain ACL for id {registered_id}; users={:?}; acl={:?}",
            user.get_users(),
            handler_state.lock().unwrap().acl
        )
    });
    user.join_channel(channel_id);
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if user
                .get_users()
                .iter()
                .any(|u| u.session_id == session && u.channel_id == channel_id && u.is_suppressed)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .unwrap_or_else(|_| {
        panic!(
            "Murmur must apply denied Speak to registered id {registered_id}; users={:?}; acl={:?}",
            user.get_users(),
            handler_state.lock().unwrap().acl
        )
    });
    let rule = acl.entries.last_mut().unwrap();
    rule.deny = 0;
    rule.grant = 0x8;
    tokio::time::sleep(Duration::from_secs(2)).await;
    client.set_channel_acl(acl);
    // Mumble 1.5.915 sends suppress=true even when it clears suppression
    // (fixed upstream in Server::clearACLCache). Permissions are immediately
    // correct; reconnect to obtain a fresh authoritative UserState snapshot.
    user.request_channel_permissions(channel_id);
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if user
                .get_channels()
                .iter()
                .any(|c| c.id == channel_id && c.permissions.is_some_and(|p| p & 8 != 0))
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Murmur must restore effective Speak permission");
    user.connect(
        "127.0.0.1".into(),
        64739,
        "AclUser".into(),
        None,
        Some(identity.cert_pem),
        Some(identity.key_pem),
        Some(fingerprint),
    );
    tokio::time::timeout(Duration::from_secs(5), user_connected.notified())
        .await
        .unwrap();
    let session = user.get_my_session().unwrap();
    user.join_channel(channel_id);
    tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            if user
                .get_users()
                .iter()
                .any(|u| u.session_id == session && u.channel_id == channel_id && !u.is_suppressed)
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
    })
    .await
    .expect("Restored Speak must be reflected after reconnect");
    // Standard channel listeners, links, and metadata edits round-trip through Murmur.
    user.set_channel_listening(0, true);
    wait_for(|| {
        user.get_users()
            .iter()
            .any(|u| u.session_id == session && u.listening_channels.contains(&0))
    })
    .await;
    user.set_channel_listening(0, false);
    wait_for(|| {
        user.get_users()
            .iter()
            .any(|u| u.session_id == session && !u.listening_channels.contains(&0))
    })
    .await;
    client.edit_channel(channel_id, "Updated fixture".into(), Some(0), 17, 8);
    wait_for(|| {
        client.get_channels().iter().any(|c| {
            c.id == channel_id
                && c.name == "Updated fixture"
                && c.position == 17
                && c.max_users == 8
        })
    })
    .await;
    client.set_channel_link(channel_id, 0, true);
    wait_for(|| {
        client
            .get_channels()
            .iter()
            .any(|c| c.id == channel_id && c.links.contains(&0))
    })
    .await;
    client.set_channel_link(channel_id, 0, false);
    wait_for(|| {
        client
            .get_channels()
            .iter()
            .any(|c| c.id == channel_id && !c.links.contains(&0))
    })
    .await;
    user.set_comment("Clear-on-exit integration fixture".into());
    wait_for(|| {
        client.get_users().iter().any(|u| {
            u.session_id == session
                && u.comment.as_deref() == Some("Clear-on-exit integration fixture")
        })
    })
    .await;
    user.clear_comment_and_disconnect();
    wait_for(|| !client.get_users().iter().any(|u| u.session_id == session)).await;

    client.remove_channel(channel_id);
    client.disconnect();
}

#[tokio::test]
async fn test_live_voice_stereo_and_deafening() {
    let failure = Arc::new(Mutex::new(None));
    assert!(mumble_core::connection::connect_tls(
        "127.0.0.1",
        64738,
        None,
        None,
        "127.0.0.1",
        64738,
        None,
        Arc::clone(&failure)
    )
    .await
    .is_err());
    let pin = failure.lock().unwrap().take().unwrap().fingerprint;
    let mut clients = Vec::new();
    for name in ["SwimbleVoiceSender", "SwimbleVoiceReceiver"] {
        let connected = Arc::new(Notify::new());
        let handler = TestHandler::new(
            Arc::clone(&connected),
            Arc::new(Notify::new()),
            Arc::new(Notify::new()),
        );
        let client = MumbleClient::new(Box::new(handler));
        let identity = generate_client_identity(name.into());
        client.connect(
            "127.0.0.1".into(),
            64738,
            name.into(),
            None,
            Some(identity.cert_pem),
            Some(identity.key_pem),
            Some(pin.clone()),
        );
        tokio::time::timeout(Duration::from_secs(5), connected.notified())
            .await
            .unwrap();
        clients.push(client);
    }
    let sender = &clients[0];
    let receiver = &clients[1];
    receiver.configure_spatial_audio(true, false, 10);
    let samples: Vec<f32> = (0..960)
        .map(|i| (i as f32 * 2.0 * std::f32::consts::PI * 440.0 / 48000.0).sin() * 0.2)
        .collect();
    let mut energy = [0.0f32; 2];
    for _ in 0..30 {
        sender.push_mic_pcm(samples.clone(), None);
        tokio::time::sleep(Duration::from_millis(20)).await;
        let out = receiver.pull_speaker_pcm(960);
        assert_eq!(out.len(), 1920);
        for pair in out.chunks_exact(2) {
            energy[0] += pair[0] * pair[0];
            energy[1] += pair[1] * pair[1];
        }
    }
    sender.finish_mic_stream(None);
    assert!(
        energy.iter().sum::<f32>() > 0.1,
        "Voice must traverse Murmur and decode to PCM: {energy:?}"
    );
    assert!(
        (energy[0] - energy[1]).abs() > 0.01,
        "Spatial playback must produce different stereo channels: {energy:?}"
    );
    receiver.set_self_deaf(true);
    assert!(receiver.pull_speaker_pcm(960).iter().all(|&s| s == 0.0));
    for client in clients {
        client.disconnect();
    }
}

async fn wait_for(mut condition: impl FnMut() -> bool) {
    tokio::time::timeout(Duration::from_secs(5), async {
        while !condition() {
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
    })
    .await
    .expect("Murmur did not acknowledge the operation");
}

#[tokio::test]
async fn native_audio_bridge_recording_and_forced_tcp() {
    let failure = Arc::new(Mutex::new(None));
    let _ = mumble_core::connection::connect_tls(
        "127.0.0.1",
        64738,
        None,
        None,
        "127.0.0.1",
        64738,
        None,
        Arc::clone(&failure),
    )
    .await;
    let fingerprint = failure.lock().unwrap().take().unwrap().fingerprint;
    let mut clients = Vec::new();
    for label in ["Recorder", "Source"] {
        let connected = Arc::new(Notify::new());
        let handler = TestHandler::new(
            Arc::clone(&connected),
            Arc::new(Notify::new()),
            Arc::new(Notify::new()),
        );
        let client = MumbleClient::new(Box::new(handler));
        client.configure_network(true, true, String::new());
        let identity = generate_client_identity(label.into());
        client.connect(
            "127.0.0.1".into(),
            64738,
            format!("{label}{}", std::process::id()),
            None,
            Some(identity.cert_pem),
            Some(identity.key_pem),
            Some(fingerprint.clone()),
        );
        tokio::time::timeout(Duration::from_secs(5), connected.notified())
            .await
            .unwrap();
        clients.push(client);
    }
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("aligned.wav");
    let receiver = &clients[0];
    let sender = &clients[1];
    let handle = Arc::clone(receiver).audio_port_handle();
    unsafe {
        mumble_core::audio_io::swimble_audio_active(handle, true);
    }
    assert!(receiver.start_recording(path.to_str().unwrap().into()));
    let tone: Vec<f32> = (0..960)
        .map(|i| (i as f32 * 440.0 * 2.0 * std::f32::consts::PI / 48000.0).sin() * 0.2)
        .collect();
    let microphone = [0.12; 960];
    let mut left = [0.0; 960];
    let mut right = [0.0; 960];
    let blocks = std::env::var("SWIMBLE_PROFILE_BLOCKS")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or(50)
        .clamp(50, 3000);
    for _ in 0..blocks {
        sender.push_mic_pcm(tone.clone(), None);
        unsafe {
            mumble_core::audio_io::swimble_audio_capture(
                handle,
                microphone.as_ptr(),
                960,
                48000,
                1.0,
                -1,
            );
            mumble_core::audio_io::swimble_audio_playback(
                handle,
                left.as_mut_ptr(),
                right.as_mut_ptr(),
                960,
                1.0,
            );
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    receiver.stop_recording();
    unsafe {
        mumble_core::audio_io::swimble_audio_active(handle, false);
        mumble_core::audio_io::swimble_audio_release(handle);
    }
    let reader = hound::WavReader::open(&path).unwrap();
    assert!(
        ((blocks * 900)..(blocks * 1200)).contains(&reader.duration()),
        "Duplex recording must use one sample clock, got {} frames",
        reader.duration()
    );
    let mut energy = [0u64; 2];
    for (i, sample) in reader.into_samples::<i16>().enumerate() {
        energy[i % 2] += sample.unwrap().unsigned_abs() as u64;
    }
    assert!(
        energy[0] > 100000 && energy[1] > 100000,
        "Both recording tracks must contain audio: {energy:?}"
    );
    assert_eq!(
        sender.get_server_connection_info().udp_packets_sent,
        0,
        "Forced TCP must suppress encrypted UDP pings and voice"
    );
    for client in clients {
        client.disconnect();
    }
}

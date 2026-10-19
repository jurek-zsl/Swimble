use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::Notify;

use mumble_core::{
    generate_client_identity, BanEntryInfo, ChannelInfo, ChatMessage, ConnectionStatus, MumbleClient,
    MumbleEventHandler, RegisteredUser, ServerConnectionInfo, TalkingState, UserInfo, UserStatsInfo,
};

#[derive(Default)]
struct TestHandlerInner {
    connection_statuses: Vec<ConnectionStatus>,
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

    fn on_user_talking_changed(&self, session_id: u32, is_talking: bool, talking_state: TalkingState) {
        println!("TestHandler: user {} talking: {} ({:?})", session_id, is_talking, talking_state);
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
        println!("TestHandler: registered users updated (count: {})", users.len());
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
    let identity = generate_client_identity("AntigravityTester".to_string());
    assert!(!identity.cert_pem.is_empty(), "Certificate PEM should not be empty");
    assert!(!identity.key_pem.is_empty(), "Key PEM should not be empty");

    // 2. Connect to local Murmur server
    println!("==> Connecting to Murmur on 127.0.0.1:64738...");
    client.connect(
        "127.0.0.1".to_string(),
        64738,
        "AntigravityTester".to_string(),
        None,
        Some(identity.cert_pem),
        Some(identity.key_pem),
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
    let root_channel = channels.iter().find(|c| c.id == 0);
    assert!(root_channel.is_some(), "Root channel (id 0) must exist");
    assert_eq!(
        root_channel.unwrap().name,
        "Root",
        "Root channel name must be 'Root'"
    );

    let users = client.get_users();
    println!("==> Discovered users: {:?}", users);
    let me = users.iter().find(|u| u.name == "AntigravityTester");
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
            if let Some(user) = client.get_users().iter().find(|u| u.session_id == my_session) {
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
    assert!(local_ping.is_ok(), "Local UDP ping to 127.0.0.1:64738 failed: {:?}", local_ping.err());
    let info = local_ping.unwrap();
    println!("Local ping info: latency={}ms, users={}/{}, version={}", info.latency_ms, info.current_users, info.max_users, info.version);
    assert!(info.latency_ms >= 0.0);

    // 2. Remote server with UDP blocked falls back to TCP connect probe
    let remote_ping = mumble_core::ping_mumble_server("mumble.gameone.dev".into(), 64738, 2000).await;
    assert!(remote_ping.is_ok(), "Remote TCP fallback ping to mumble.gameone.dev:64738 failed: {:?}", remote_ping.err());
    let remote_info = remote_ping.unwrap();
    println!("Remote ping info: latency={}ms, users={}/{}, version={}", remote_info.latency_ms, remote_info.current_users, remote_info.max_users, remote_info.version);
    assert_eq!(remote_info.version, "Online (TCP)");
    assert!(remote_info.latency_ms > 0.0);
}

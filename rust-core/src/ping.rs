use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::net::UdpSocket;
use tokio::time::timeout;
use crate::{MumbleError, ServerPingInfo};

#[uniffi::export]
pub async fn ping_mumble_server(host: String, port: u16, timeout_ms: u64) -> Result<ServerPingInfo, MumbleError> {
    let bind_addr = if host.contains(':') && !host.starts_with('[') {
        "[::]:0"
    } else {
        "0.0.0.0:0"
    };

    let socket = UdpSocket::bind(bind_addr)
        .await
        .map_err(|e| MumbleError::NetworkError(format!("Failed to bind UDP socket: {}", e)))?;

    let addr = format!("{}:{}", host, port);
    socket.connect(&addr)
        .await
        .map_err(|e| MumbleError::NetworkError(format!("Failed to connect UDP socket to {}: {}", addr, e)))?;

    // 12-byte Mumble ping probe: 0u32 + 8-byte timestamp
    let sent_ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;

    let mut probe = [0u8; 12];
    probe[0..4].copy_from_slice(&0u32.to_be_bytes());
    probe[4..12].copy_from_slice(&sent_ts.to_be_bytes());

    let start_instant = Instant::now();
    socket.send(&probe)
        .await
        .map_err(|e| MumbleError::NetworkError(format!("Failed to send UDP ping: {}", e)))?;

    let mut buf = [0u8; 128];
    let duration = Duration::from_millis(timeout_ms.max(100));

    let n = timeout(duration, socket.recv(&mut buf))
        .await
        .map_err(|_| MumbleError::NetworkError("UDP ping timed out".into()))?
        .map_err(|e| MumbleError::NetworkError(format!("Failed to recv UDP ping reply: {}", e)))?;

    if n < 24 {
        return Err(MumbleError::ProtocolError(format!("UDP ping reply too short: {} bytes (expected 24)", n)));
    }

    let latency_ms = start_instant.elapsed().as_secs_f32() * 1000.0;

    let version_raw = u32::from_be_bytes(buf[0..4].try_into().unwrap());
    let _ident = u64::from_be_bytes(buf[4..12].try_into().unwrap());
    let current_users = u32::from_be_bytes(buf[12..16].try_into().unwrap());
    let max_users = u32::from_be_bytes(buf[16..20].try_into().unwrap());
    let _bandwidth = u32::from_be_bytes(buf[20..24].try_into().unwrap());

    let major = (version_raw >> 16) & 0xFFFF;
    let minor = (version_raw >> 8) & 0xFF;
    let patch = version_raw & 0xFF;
    let version = format!("{}.{}.{}", major, minor, patch);

    Ok(ServerPingInfo {
        latency_ms,
        current_users,
        max_users,
        version,
    })
}

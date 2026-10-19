use std::net::SocketAddr;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::net::{TcpStream, UdpSocket};
use tokio::time::timeout;
use crate::{MumbleError, ServerPingInfo};

#[uniffi::export]
pub async fn ping_mumble_server(host: String, port: u16, timeout_ms: u64) -> Result<ServerPingInfo, MumbleError> {
    let trimmed = host.trim();
    let no_prefix = trimmed
        .strip_prefix("mumble://")
        .or_else(|| trimmed.strip_prefix("http://"))
        .or_else(|| trimmed.strip_prefix("https://"))
        .unwrap_or(trimmed);

    // If host has :port embedded (e.g. "127.0.0.1:64738" or "server.com:64738")
    let (target_host, target_port) = if let Some((h, p_str)) = no_prefix.rsplit_once(':') {
        if !h.contains(':') || (h.starts_with('[') && h.ends_with(']')) {
            let clean_h = h.trim_matches('[').trim_matches(']');
            if let Ok(parsed_p) = p_str.parse::<u16>() {
                (clean_h, parsed_p)
            } else {
                (clean_h, port)
            }
        } else {
            (no_prefix, port)
        }
    } else {
        (no_prefix, port)
    };

    // Resolve address list via Tokio DNS lookup
    let addrs: Vec<SocketAddr> = match tokio::net::lookup_host((target_host, target_port)).await {
        Ok(iter) => iter.collect(),
        Err(e) => {
            return Err(MumbleError::NetworkError(format!(
                "DNS lookup failed for {}:{}: {}",
                target_host, target_port, e
            )));
        }
    };

    if addrs.is_empty() {
        return Err(MumbleError::NetworkError(format!(
            "No IP addresses resolved for {}:{}",
            target_host, target_port
        )));
    }

    let probe_timeout = timeout_ms.max(2000);
    for &addr in &addrs {
        if let Ok(info) = probe_address(addr, probe_timeout).await {
            return Ok(info);
        }
    }

    Err(MumbleError::NetworkError(format!(
        "Server {}:{} is unreachable",
        target_host, target_port
    )))
}

async fn probe_address(addr: SocketAddr, timeout_ms: u64) -> Result<ServerPingInfo, MumbleError> {
    let udp_timeout = Duration::from_millis(timeout_ms.min(1000).max(400));
    let tcp_timeout = Duration::from_millis(timeout_ms.max(1500));

    let udp_fut = ping_udp_target(addr, udp_timeout);
    let tcp_fut = ping_tcp_target(addr, tcp_timeout);
    tokio::pin!(udp_fut);
    tokio::pin!(tcp_fut);

    tokio::select! {
        udp_res = &mut udp_fut => {
            if let Ok(info) = udp_res {
                return Ok(info);
            }
            // UDP failed (e.g. dropped/firewalled), wait for TCP
            tcp_fut.await
        }
        tcp_res = &mut tcp_fut => {
            if let Ok(tcp_info) = tcp_res {
                // TCP succeeded fast! Give UDP up to 350ms to finish so we might get full stats
                let extra_udp_wait = tokio::time::timeout(Duration::from_millis(350), &mut udp_fut);
                if let Ok(Ok(udp_info)) = extra_udp_wait.await {
                    return Ok(udp_info);
                }
                return Ok(tcp_info);
            }
            // TCP failed, wait for UDP
            udp_fut.await
        }
    }
}

async fn ping_udp_target(addr: SocketAddr, timeout_dur: Duration) -> Result<ServerPingInfo, MumbleError> {
    let bind_addr = if addr.is_ipv6() { "[::]:0" } else { "0.0.0.0:0" };
    let socket = UdpSocket::bind(bind_addr)
        .await
        .map_err(|e| MumbleError::NetworkError(format!("Failed to bind UDP socket: {}", e)))?;

    socket.connect(addr)
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
    let n = timeout(timeout_dur, socket.recv(&mut buf))
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

async fn ping_tcp_target(addr: SocketAddr, timeout_dur: Duration) -> Result<ServerPingInfo, MumbleError> {
    let start_instant = Instant::now();
    let stream = timeout(timeout_dur, TcpStream::connect(addr))
        .await
        .map_err(|_| MumbleError::NetworkError(format!("TCP connection to {} timed out", addr)))?
        .map_err(|e| MumbleError::NetworkError(format!("Failed to connect TCP to {}: {}", addr, e)))?;

    let latency_ms = start_instant.elapsed().as_secs_f32() * 1000.0;
    drop(stream);

    Ok(ServerPingInfo {
        latency_ms,
        current_users: 0,
        max_users: 0,
        version: "Online (TCP)".to_string(),
    })
}

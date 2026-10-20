use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub const TYPE_VERSION: u16 = 0;
pub const TYPE_UDP_TUNNEL: u16 = 1;
pub const TYPE_AUTHENTICATE: u16 = 2;
pub const TYPE_PING: u16 = 3;
pub const TYPE_REJECT: u16 = 4;
pub const TYPE_SERVER_SYNC: u16 = 5;
pub const TYPE_CHANNEL_REMOVE: u16 = 6;
pub const TYPE_CHANNEL_STATE: u16 = 7;
pub const TYPE_USER_REMOVE: u16 = 8;
pub const TYPE_USER_STATE: u16 = 9;
pub const TYPE_BAN_LIST: u16 = 10;
pub const TYPE_TEXT_MESSAGE: u16 = 11;
pub const TYPE_PERMISSION_DENIED: u16 = 12;
pub const TYPE_ACL: u16 = 13;
pub const TYPE_CRYPT_SETUP: u16 = 15;
pub const TYPE_USER_LIST: u16 = 18;
pub const TYPE_VOICE_TARGET: u16 = 19;
pub const TYPE_PERMISSION_QUERY: u16 = 20;
pub const TYPE_USER_STATS: u16 = 22;
pub const TYPE_REQUEST_BLOB: u16 = 23;
pub const TYPE_SERVER_CONFIG: u16 = 24;

#[derive(Clone, Debug, PartialEq)]
pub struct RawPacket {
    pub type_id: u16,
    pub payload: Vec<u8>,
}

pub async fn read_packet<R: AsyncReadExt + Unpin>(reader: &mut R) -> std::io::Result<RawPacket> {
    let mut header = [0u8; 6];
    tokio::time::timeout(
        std::time::Duration::from_secs(60),
        reader.read_exact(&mut header),
    )
    .await
    .map_err(|_| {
        std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "Mumble server stopped responding",
        )
    })??;
    let type_id = u16::from_be_bytes([header[0], header[1]]);
    let length = u32::from_be_bytes([header[2], header[3], header[4], header[5]]) as usize;
    if length > 8 * 1024 * 1024 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "Mumble frame exceeds 8 MiB",
        ));
    }
    let mut payload = vec![0u8; length];
    tokio::time::timeout(
        std::time::Duration::from_secs(30),
        reader.read_exact(&mut payload),
    )
    .await
    .map_err(|_| std::io::Error::new(std::io::ErrorKind::TimedOut, "Mumble frame timed out"))??;
    Ok(RawPacket { type_id, payload })
}

pub async fn write_raw_packet<W: AsyncWriteExt + Unpin>(
    writer: &mut W,
    type_id: u16,
    payload: &[u8],
) -> std::io::Result<()> {
    let mut header = [0u8; 6];
    header[0..2].copy_from_slice(&type_id.to_be_bytes());
    header[2..6].copy_from_slice(&(payload.len() as u32).to_be_bytes());
    writer.write_all(&header).await?;
    writer.write_all(payload).await?;
    writer.flush().await?;
    Ok(())
}

pub async fn write_proto_packet<W: AsyncWriteExt + Unpin, M: prost::Message>(
    writer: &mut W,
    type_id: u16,
    msg: &M,
) -> std::io::Result<()> {
    let payload = msg.encode_to_vec();
    write_raw_packet(writer, type_id, &payload).await
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn oversized_frame_is_rejected_before_reading_payload() {
        let bytes = [0u8, 0, 255, 255, 255, 255];
        assert_eq!(
            read_packet(&mut &bytes[..]).await.unwrap_err().kind(),
            std::io::ErrorKind::InvalidData
        );
    }
    #[tokio::test]
    async fn fragmented_frame_roundtrips() {
        let (mut tx, mut rx) = tokio::io::duplex(8);
        let task = tokio::spawn(async move {
            write_raw_packet(&mut tx, 11, b"fragmented payload")
                .await
                .unwrap()
        });
        let p = read_packet(&mut rx).await.unwrap();
        assert_eq!(p.type_id, 11);
        assert_eq!(p.payload, b"fragmented payload");
        task.await.unwrap();
    }
}

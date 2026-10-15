#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum VoicePacketError {
    UnexpectedEof,
    InvalidVarInt,
    UnsupportedCodec(u8),
    InvalidPacketType,
}

impl std::fmt::Display for VoicePacketError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for VoicePacketError {}

/// Mumble VarInt encoder
pub fn encode_varint(value: u64, buf: &mut Vec<u8>) {
    let mut i = value;
    if (i & 0x8000000000000000) != 0 && (!i < 0x100000000) {
        // Signed / negative number
        i = !i;
        if i <= 0x3 {
            buf.push(0xFC | (i as u8));
            return;
        } else {
            buf.push(0xF8);
        }
    }

    if i < 0x80 {
        buf.push(i as u8);
    } else if i < 0x4000 {
        buf.push(((i >> 8) as u8) | 0x80);
        buf.push((i & 0xFF) as u8);
    } else if i < 0x200000 {
        buf.push(((i >> 16) as u8) | 0xC0);
        buf.push(((i >> 8) & 0xFF) as u8);
        buf.push((i & 0xFF) as u8);
    } else if i < 0x10000000 {
        buf.push(((i >> 24) as u8) | 0xE0);
        buf.push(((i >> 16) & 0xFF) as u8);
        buf.push(((i >> 8) & 0xFF) as u8);
        buf.push((i & 0xFF) as u8);
    } else if i < 0x100000000 {
        buf.push(0xF0);
        buf.extend_from_slice(&(i as u32).to_be_bytes());
    } else {
        buf.push(0xF4);
        buf.extend_from_slice(&i.to_be_bytes());
    }
}

/// Mumble VarInt decoder returning (value, bytes_consumed)
pub fn decode_varint(data: &[u8]) -> Result<(u64, usize), VoicePacketError> {
    if data.is_empty() {
        return Err(VoicePacketError::UnexpectedEof);
    }
    let v = data[0] as u64;
    if (v & 0x80) == 0 {
        Ok((v & 0x7F, 1))
    } else if (v & 0xC0) == 0x80 {
        if data.len() < 2 {
            return Err(VoicePacketError::UnexpectedEof);
        }
        let res = ((v & 0x3F) << 8) | (data[1] as u64);
        Ok((res, 2))
    } else if (v & 0xF0) == 0xF0 {
        match v & 0xFC {
            0xF0 => {
                if data.len() < 5 {
                    return Err(VoicePacketError::UnexpectedEof);
                }
                let res = u32::from_be_bytes(data[1..5].try_into().unwrap()) as u64;
                Ok((res, 5))
            }
            0xF4 => {
                if data.len() < 9 {
                    return Err(VoicePacketError::UnexpectedEof);
                }
                let res = u64::from_be_bytes(data[1..9].try_into().unwrap());
                Ok((res, 9))
            }
            0xF8 => {
                let (inner, read) = decode_varint(&data[1..])?;
                Ok((!inner, 1 + read))
            }
            0xFC => Ok((!(v & 0x03), 1)),
            _ => Err(VoicePacketError::InvalidVarInt),
        }
    } else if (v & 0xF0) == 0xE0 {
        if data.len() < 4 {
            return Err(VoicePacketError::UnexpectedEof);
        }
        let res = ((v & 0x0F) << 24)
            | ((data[1] as u64) << 16)
            | ((data[2] as u64) << 8)
            | (data[3] as u64);
        Ok((res, 4))
    } else if (v & 0xE0) == 0xC0 {
        if data.len() < 3 {
            return Err(VoicePacketError::UnexpectedEof);
        }
        let res = ((v & 0x1F) << 16) | ((data[1] as u64) << 8) | (data[2] as u64);
        Ok((res, 3))
    } else {
        Err(VoicePacketError::InvalidVarInt)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct ClientVoicePacket {
    pub target: u8,
    pub sequence: u64,
    pub is_terminator: bool,
    pub opus_payload: Vec<u8>,
}

pub fn encode_client_voice(packet: &ClientVoicePacket) -> Vec<u8> {
    let mut buf = Vec::with_capacity(packet.opus_payload.len() + 16);
    // Header byte: Opus is type 4 (4 << 5 = 0x80)
    let header = 0x80 | (packet.target & 0x1F);
    buf.push(header);

    // Sequence number
    encode_varint(packet.sequence, &mut buf);

    // Opus length and terminator flag (13-bit length + 14th terminator bit)
    let len_flag = (packet.opus_payload.len() as u64 & 0x1FFF)
        | if packet.is_terminator { 0x2000 } else { 0 };
    encode_varint(len_flag, &mut buf);

    // Opus payload
    buf.extend_from_slice(&packet.opus_payload);
    buf
}

#[derive(Clone, Debug, PartialEq)]
pub struct ServerVoicePacket {
    pub codec: u8,
    pub target: u8,
    pub session_id: u32,
    pub sequence: u64,
    pub is_terminator: bool,
    pub opus_payload: Vec<u8>,
    pub positional_data: Option<[f32; 3]>,
}

pub fn decode_server_voice(data: &[u8]) -> Result<ServerVoicePacket, VoicePacketError> {
    if data.is_empty() {
        return Err(VoicePacketError::UnexpectedEof);
    }
    let header = data[0];
    let codec = (header >> 5) & 0x07;
    let target = header & 0x1F;

    let mut offset = 1;

    // Session ID
    let (session_id_u64, len) = decode_varint(&data[offset..])?;
    offset += len;
    let session_id = session_id_u64 as u32;

    // Sequence number
    let (sequence, len) = decode_varint(&data[offset..])?;
    offset += len;

    // Opus is codec == 4
    if codec == 4 {
        let (len_flag, len) = decode_varint(&data[offset..])?;
        offset += len;

        let opus_len = (len_flag & 0x1FFF) as usize;
        let is_terminator = (len_flag & 0x2000) != 0;

        if data.len() < offset + opus_len {
            return Err(VoicePacketError::UnexpectedEof);
        }

        let opus_payload = data[offset..offset + opus_len].to_vec();
        offset += opus_len;

        let positional_data = if data.len() >= offset + 12 {
            let x = f32::from_le_bytes(data[offset..offset + 4].try_into().unwrap());
            let y = f32::from_le_bytes(data[offset + 4..offset + 8].try_into().unwrap());
            let z = f32::from_le_bytes(data[offset + 8..offset + 12].try_into().unwrap());
            Some([x, y, z])
        } else {
            None
        };

        Ok(ServerVoicePacket {
            codec,
            target,
            session_id,
            sequence,
            is_terminator,
            opus_payload,
            positional_data,
        })
    } else {
        Err(VoicePacketError::UnsupportedCodec(codec))
    }
}

pub fn encode_udp_ping(timestamp: u64) -> Vec<u8> {
    let mut buf = Vec::with_capacity(16);
    // Ping packet header is 0x20 (type 1 << 5)
    buf.push(0x20);
    encode_varint(timestamp, &mut buf);
    buf
}

#[derive(Clone, Debug, PartialEq)]
pub struct UdpPingReply {
    pub timestamp: u64,
    pub good: u32,
    pub late: u32,
    pub lost: u32,
    pub resync: u32,
}

pub fn decode_udp_ping_reply(data: &[u8]) -> Result<UdpPingReply, VoicePacketError> {
    if data.is_empty() || (data[0] >> 5) != 1 {
        return Err(VoicePacketError::InvalidPacketType);
    }
    let mut offset = 1;
    let (timestamp, len) = decode_varint(&data[offset..])?;
    offset += len;

    let (good, len) = decode_varint(&data[offset..]).unwrap_or((0, 0));
    offset += len;
    let (late, len) = decode_varint(&data[offset..]).unwrap_or((0, 0));
    offset += len;
    let (lost, len) = decode_varint(&data[offset..]).unwrap_or((0, 0));
    offset += len;
    let (resync, _) = decode_varint(&data[offset..]).unwrap_or((0, 0));

    Ok(UdpPingReply {
        timestamp,
        good: good as u32,
        late: late as u32,
        lost: lost as u32,
        resync: resync as u32,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_varint_roundtrip() {
        let test_values = [
            0,
            1,
            127,
            128,
            16383,
            16384,
            2097151,
            2097152,
            268435455,
            268435456,
            4294967295,
            4294967296,
            1234567890123456,
        ];

        for &val in &test_values {
            let mut buf = Vec::new();
            encode_varint(val, &mut buf);
            let (decoded, consumed) = decode_varint(&buf).unwrap();
            assert_eq!(decoded, val);
            assert_eq!(consumed, buf.len());
        }
    }

    #[test]
    fn test_client_voice_packet_roundtrip() {
        let client_packet = ClientVoicePacket {
            target: 0,
            sequence: 42,
            is_terminator: true,
            opus_payload: vec![1, 2, 3, 4, 5, 6, 7, 8],
        };

        let encoded = encode_client_voice(&client_packet);
        assert_eq!(encoded[0], 0x80); // Opus normal target

        // Simulate server prepending session_id
        let mut server_bytes = Vec::new();
        server_bytes.push(encoded[0]);
        encode_varint(1337, &mut server_bytes); // session ID
        server_bytes.extend_from_slice(&encoded[1..]);

        let decoded = decode_server_voice(&server_bytes).unwrap();
        assert_eq!(decoded.codec, 4);
        assert_eq!(decoded.target, 0);
        assert_eq!(decoded.session_id, 1337);
        assert_eq!(decoded.sequence, 42);
        assert!(decoded.is_terminator);
        assert_eq!(decoded.opus_payload, vec![1, 2, 3, 4, 5, 6, 7, 8]);
    }

    #[test]
    fn test_udp_ping_roundtrip() {
        let ts = 9876543210;
        let ping_bytes = encode_udp_ping(ts);
        assert_eq!(ping_bytes[0], 0x20);

        let reply = decode_udp_ping_reply(&ping_bytes).unwrap();
        assert_eq!(reply.timestamp, ts);
    }
}

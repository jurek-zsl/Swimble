use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::voice_packet::{ClientVoicePacket, ServerVoicePacket};
use crate::TalkingState;

const SAMPLE_RATE: u32 = 48000;
const FRAME_SIZE: usize = 480; // 10ms frame at 48kHz
const BITRATE_BPS: i32 = 64000;
const TALKING_TIMEOUT: Duration = Duration::from_millis(350);

pub struct UserAudioState {
    pub session_id: u32,
    pub decoder: opus::Decoder,
    pub jitter_queue: VecDeque<Vec<f32>>,
    pub last_packet_time: Instant,
    pub is_talking: bool,
    pub talking_state: TalkingState,
}

impl UserAudioState {
    pub fn new(session_id: u32) -> Result<Self, opus::Error> {
        let decoder = opus::Decoder::new(SAMPLE_RATE, opus::Channels::Mono)?;
        Ok(Self {
            session_id,
            decoder,
            jitter_queue: VecDeque::new(),
            last_packet_time: Instant::now(),
            is_talking: false,
            talking_state: TalkingState::Passive,
        })
    }
}

pub struct AudioMixer {
    encoder: opus::Encoder,
    mic_accumulator: Vec<f32>,
    users: HashMap<u32, UserAudioState>,
    speaker_producer: rtrb::Producer<f32>,
    mic_sequence: u64,
}

impl AudioMixer {
    pub fn new(speaker_producer: rtrb::Producer<f32>) -> Result<Self, opus::Error> {
        let mut encoder =
            opus::Encoder::new(SAMPLE_RATE, opus::Channels::Mono, opus::Application::Voip)?;
        let _ = encoder.set_bitrate(opus::Bitrate::Bits(BITRATE_BPS));

        Ok(Self {
            encoder,
            mic_accumulator: Vec::with_capacity(FRAME_SIZE * 4),
            users: HashMap::new(),
            speaker_producer,
            mic_sequence: 0,
        })
    }

    /// Pushes mic PCM float samples from macOS audio engine.
    /// Sets the target field (0 = normal channel, 1..30 = whisper/shout).
    pub fn push_mic_pcm(&mut self, samples: &[f32], target: u8) -> Vec<ClientVoicePacket> {
        self.mic_accumulator.extend_from_slice(samples);
        let mut packets = Vec::new();
        let mut opus_buf = [0u8; 1024];

        while self.mic_accumulator.len() >= FRAME_SIZE {
            let frame: Vec<f32> = self.mic_accumulator.drain(..FRAME_SIZE).collect();
            if let Ok(len) = self.encoder.encode_float(&frame, &mut opus_buf) {
                let packet = ClientVoicePacket {
                    target: target & 0x1F,
                    sequence: self.mic_sequence,
                    is_terminator: false,
                    opus_payload: opus_buf[..len].to_vec(),
                };
                self.mic_sequence = self.mic_sequence.wrapping_add(1);
                packets.push(packet);
            }
        }

        packets
    }

    /// Flushes any remaining mic audio as a terminator packet
    pub fn finish_mic_stream(&mut self, target: u8) -> Option<ClientVoicePacket> {
        if self.mic_accumulator.is_empty() {
            return None;
        }
        // Pad to full frame
        self.mic_accumulator.resize(FRAME_SIZE, 0.0);
        let frame: Vec<f32> = self.mic_accumulator.drain(..FRAME_SIZE).collect();
        let mut opus_buf = [0u8; 1024];

        if let Ok(len) = self.encoder.encode_float(&frame, &mut opus_buf) {
            let packet = ClientVoicePacket {
                target: target & 0x1F,
                sequence: self.mic_sequence,
                is_terminator: true,
                opus_payload: opus_buf[..len].to_vec(),
            };
            self.mic_sequence = self.mic_sequence.wrapping_add(1);
            Some(packet)
        } else {
            None
        }
    }

    /// Decodes and mixes an incoming server voice packet.
    /// Returns talking state changes: Some((session_id, is_talking, talking_state))
    pub fn process_incoming_voice(
        &mut self,
        packet: ServerVoicePacket,
        volumes: &HashMap<u32, f32>,
    ) -> Option<(u32, bool, TalkingState)> {
        let session_id = packet.session_id;
        let is_terminator = packet.is_terminator;

        let user = self.users.entry(session_id).or_insert_with(|| {
            UserAudioState::new(session_id).expect("Failed to initialize user Opus decoder")
        });

        user.last_packet_time = Instant::now();

        let new_state = if is_terminator {
            TalkingState::Passive
        } else if packet.target == 0 {
            TalkingState::Talking
        } else if packet.target <= 2 {
            TalkingState::Whisper
        } else {
            TalkingState::Shout
        };

        let mut talking_event = None;
        if is_terminator {
            if user.is_talking {
                user.is_talking = false;
                user.talking_state = TalkingState::Passive;
                talking_event = Some((session_id, false, TalkingState::Passive));
            }
        } else if !user.is_talking || user.talking_state != new_state {
            user.is_talking = true;
            user.talking_state = new_state;
            talking_event = Some((session_id, true, new_state));
        }

        // Decode packet into PCM
        let mut pcm_out = [0.0f32; 1920];
        let volume_multiplier = volumes.get(&session_id).copied().unwrap_or(1.0);

        if let Ok(samples_decoded) =
            user.decoder.decode_float(&packet.opus_payload, &mut pcm_out, false)
        {
            // Apply volume multiplier and soft-clipping, then push to ring buffer
            for &sample in &pcm_out[..samples_decoded] {
                let scaled = sample * volume_multiplier;
                let clipped = soft_clip(scaled);
                let _ = self.speaker_producer.push(clipped);
            }
        }

        talking_event
    }

    /// Checks for talking timeouts on all active user streams.
    /// Returns list of (session_id, false, TalkingState::Passive) events for silent streams.
    pub fn check_talking_timeouts(&mut self) -> Vec<(u32, bool, TalkingState)> {
        let now = Instant::now();
        let mut timed_out = Vec::new();

        for (session_id, state) in &mut self.users {
            if state.is_talking && now.duration_since(state.last_packet_time) > TALKING_TIMEOUT {
                state.is_talking = false;
                state.talking_state = TalkingState::Passive;
                timed_out.push((*session_id, false, TalkingState::Passive));
            }
        }

        timed_out
    }
}

/// Polynomial soft-clipping function: smooth compression when |x| > 0.8
#[inline]
fn soft_clip(x: f32) -> f32 {
    if x > 1.0 {
        1.0
    } else if x < -1.0 {
        -1.0
    } else if x > 0.8 {
        0.8 + (x - 0.8) / (1.0 + (x - 0.8) * (x - 0.8))
    } else if x < -0.8 {
        -0.8 + (x + 0.8) / (1.0 + (x + 0.8) * (x + 0.8))
    } else {
        x
    }
}

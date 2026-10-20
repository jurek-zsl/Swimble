use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::voice_packet::{ClientVoicePacket, ServerVoicePacket};
use crate::TalkingState;

const SAMPLE_RATE: u32 = 48000;
const FRAME_SIZE: usize = 960; // 20ms Opus packets reduce encoding/transport overhead
const BITRATE_BPS: i32 = 64000;
const TALKING_TIMEOUT: Duration = Duration::from_millis(350);
const PRIORITY_SPEAKER_ATTENUATION: f32 = 0.125; // -18 dB standard Mumble attenuation

pub struct UserAudioState {
    pub session_id: u32,
    pub decoder: opus::Decoder,
    pub jitter_queue: VecDeque<f32>,
    sequence: Option<u64>,
    packets: BTreeMap<u64, Vec<u8>>,
    last_frame_samples: usize,
    jitter_ewma: f32,
    last_arrival: Option<(u64, Instant)>,
    position: Option<[f32; 3]>,
    volume: f32,
    priority: bool,
    primed: bool,
    queued_at: Instant,
    render_gains: [f32; 2],
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
            jitter_queue: VecDeque::with_capacity(9600),
            sequence: None,
            packets: BTreeMap::new(),
            last_frame_samples: 960,
            jitter_ewma: 0.0,
            last_arrival: None,
            position: None,
            volume: 1.0,
            priority: false,
            primed: false,
            queued_at: Instant::now(),
            render_gains: [1.0, 1.0],
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
    mic_active: bool,
    spatial: bool,
    jitter_samples: usize,
    link: Option<crate::positional::MumbleLink>,
    listener: Option<crate::positional::LinkFrame>,
    pub plugin: Option<crate::plugins::PositionalPlugin>,
    pub manual_listener: Option<crate::positional::LinkFrame>,
    pub distance_settings: [f32; 4],
    self_priority_talking: bool,
    render_buffer: Vec<f32>,
    frame_size: usize,
    requested_bitrate: u32,
    server_bandwidth: u32,
    effective_bitrate: u32,
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
            mic_active: false,
            spatial: false,
            jitter_samples: 480,
            link: None,
            listener: None,
            plugin: None,
            manual_listener: None,
            distance_settings: [1.0, 50.0, 0.0, 0.25],
            self_priority_talking: false,
            render_buffer: vec![0.0; 16384],
            frame_size: FRAME_SIZE,
            requested_bitrate: 64000,
            server_bandwidth: 0,
            effective_bitrate: 64000,
        })
    }

    pub fn configure_quality(&mut self, bitrate: u32, packet_ms: u32, fec: bool) {
        self.requested_bitrate = bitrate.clamp(6000, 128000);
        self.frame_size = match packet_ms {
            10 => 480,
            40 => 1920,
            60 => 2880,
            _ => 960,
        };
        let _ = self.encoder.set_inband_fec(fec);
        let _ = self.encoder.set_packet_loss_perc(if fec { 10 } else { 0 });
        self.apply_bitrate();
    }
    pub fn set_server_bandwidth(&mut self, bandwidth: u32) {
        self.server_bandwidth = bandwidth;
        self.apply_bitrate();
    }
    fn apply_bitrate(&mut self) {
        let overhead = 48 * 8 * 48000 / self.frame_size as u32;
        let budget = if self.server_bandwidth == 0 {
            128000
        } else {
            self.server_bandwidth.saturating_sub(overhead).max(6000)
        };
        self.effective_bitrate = self.requested_bitrate.min(budget);
        let _ = self
            .encoder
            .set_bitrate(opus::Bitrate::Bits(self.effective_bitrate as i32));
    }
    pub fn bitrate(&self) -> u32 {
        self.effective_bitrate
    }

    /// Pushes mic PCM float samples from macOS audio engine.
    /// Sets the target field (0 = normal channel, 1..30 = whisper/shout).
    pub fn push_mic_pcm(&mut self, samples: &[f32], target: u8) -> Vec<ClientVoicePacket> {
        self.mic_active = true;
        self.mic_accumulator.extend_from_slice(samples);
        let mut packets = Vec::new();
        let mut opus_buf = [0u8; 1024];

        while self.mic_accumulator.len() >= self.frame_size {
            if let Ok(len) = self
                .encoder
                .encode_float(&self.mic_accumulator[..self.frame_size], &mut opus_buf)
            {
                let packet = ClientVoicePacket {
                    target: target & 0x1F,
                    sequence: self.mic_sequence,
                    is_terminator: false,
                    opus_payload: opus_buf[..len].to_vec(),
                    positional_data: self.listener.as_ref().map(|l| l.avatar),
                };
                self.mic_sequence = self
                    .mic_sequence
                    .wrapping_add((self.frame_size / 480) as u64);
                packets.push(packet);
            }
            self.mic_accumulator.drain(..self.frame_size);
        }

        packets
    }

    /// Flushes any remaining mic audio as a terminator packet
    pub fn finish_mic_stream(&mut self, target: u8) -> Option<ClientVoicePacket> {
        if !self.mic_active {
            return None;
        }
        self.mic_active = false;
        // Pad to full frame
        self.mic_accumulator.resize(self.frame_size, 0.0);
        let frame: Vec<f32> = self.mic_accumulator.drain(..self.frame_size).collect();
        let mut opus_buf = [0u8; 1024];

        if let Ok(len) = self.encoder.encode_float(&frame, &mut opus_buf) {
            let packet = ClientVoicePacket {
                target: target & 0x1F,
                sequence: self.mic_sequence,
                is_terminator: true,
                opus_payload: opus_buf[..len].to_vec(),
                positional_data: self.listener.as_ref().map(|l| l.avatar),
            };
            self.mic_sequence = self
                .mic_sequence
                .wrapping_add((self.frame_size / 480) as u64);
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
        volume: f32,
        priority: bool,
        self_priority_talking: bool,
    ) -> Option<(u32, bool, TalkingState)> {
        if packet.opus_payload.len() > 8192 {
            return None;
        }
        let session_id = packet.session_id;
        let is_terminator = packet.is_terminator;

        self.self_priority_talking = self_priority_talking;
        let user = self.users.entry(session_id).or_insert_with(|| {
            UserAudioState::new(session_id).expect("Failed to initialize user Opus decoder")
        });

        if user.sequence.is_some_and(|next| packet.sequence < next)
            || user.packets.contains_key(&packet.sequence)
        {
            return None;
        }
        let now = Instant::now();
        if let Some((seq, at)) = user.last_arrival {
            let expected_ms = packet.sequence.saturating_sub(seq) as f32 * 10.0;
            if packet.sequence > seq {
                let deviation = (now.duration_since(at).as_secs_f32() * 1000.0 - expected_ms).abs();
                user.jitter_ewma += (deviation - user.jitter_ewma) / 16.0;
            }
        }
        if user
            .last_arrival
            .is_none_or(|(seq, _)| packet.sequence > seq)
        {
            user.last_arrival = Some((packet.sequence, now));
        }
        user.last_packet_time = Instant::now();
        user.position = packet
            .positional_data
            .filter(|p| p.iter().all(|x| x.is_finite()));
        user.volume = (volume * packet.volume_adjustment).clamp(0.0, 4.0);
        user.priority = priority;

        let new_state = if is_terminator {
            TalkingState::Passive
        } else if packet.target == 0 {
            TalkingState::Talking
        } else if packet.target == 1 {
            TalkingState::Shout
        } else if packet.target == 2 {
            TalkingState::Whisper
        } else {
            TalkingState::Talking
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

        if !packet.opus_payload.is_empty() {
            if user.packets.is_empty() && user.jitter_queue.is_empty() && !user.primed {
                user.queued_at = Instant::now();
            }
            if user.packets.len() < 32 {
                user.packets.insert(packet.sequence, packet.opus_payload);
            }
        }

        talking_event
    }

    pub fn configure_spatial(&mut self, spatial: bool, link: bool, jitter_ms: u32) {
        self.spatial = spatial;
        self.jitter_samples = jitter_ms.clamp(10, 100) as usize * 48;
        if link && self.link.is_none() {
            self.link = crate::positional::MumbleLink::open();
        }
        if !link {
            self.link = None;
            self.listener = None;
        }
    }

    pub fn poll_link(&mut self) -> Option<(Vec<u8>, String)> {
        self.listener = self
            .manual_listener
            .clone()
            .or_else(|| self.plugin.as_mut().and_then(|p| p.read()))
            .or_else(|| self.link.as_mut().and_then(|link| link.read()));
        self.listener
            .as_ref()
            .map(|l| (l.context.clone(), l.identity.clone()))
    }

    pub fn positioning_diagnostics(&self) -> String {
        match &self.listener {
            Some(l) => format!(
                "Source: {}\nAvatar: {:?}\nCamera: {:?}\nFront: {:?}\nContext: {:?}\nIdentity: {}",
                if self.manual_listener.is_some() {
                    "Manual"
                } else if self.plugin.is_some() {
                    "Native plugin"
                } else {
                    "Mumble Link"
                },
                l.avatar,
                l.camera,
                l.front,
                String::from_utf8_lossy(&l.context),
                l.identity
            ),
            None => format!(
                "No active position source.\nPlugin: {}\nLink attached: {}",
                self.plugin
                    .as_ref()
                    .map(|p| p.path.as_str())
                    .unwrap_or("none"),
                self.link.is_some()
            ),
        }
    }

    pub fn reset(&mut self) {
        self.users.clear();
        self.mic_accumulator.clear();
        self.mic_active = false;
        self.mic_sequence = 0;
        self.self_priority_talking = false;
    }

    /// Stereo interleaved 48kHz output, summing concurrent speakers once per block.
    /// Render only on hardware demand: no mixer timer or work while disconnected.
    pub fn render(&mut self, frames: usize, deafened: bool) {
        let priority =
            self.self_priority_talking || self.users.values().any(|u| u.priority && u.is_talking);
        for u in self.users.values_mut() {
            let gain = if priority && !u.priority {
                PRIORITY_SPEAKER_ATTENUATION
            } else {
                1.0
            } * u.volume;
            let gains = if let (Some(position), Some(listener)) = (u.position, &self.listener) {
                crate::positional::gains_configured(position, listener, self.distance_settings)
            } else if self.spatial {
                // Stable virtual seating; no transmitted fake game coordinates.
                crate::positional::stereo_pan(
                    ((u.session_id.wrapping_mul(2654435761) % 1000) as f32 / 999.0 - 0.5) * 1.5,
                )
            } else {
                [1.0, 1.0]
            };
            u.render_gains = gains.map(|g| g * gain);
            let target = self
                .jitter_samples
                .max((u.jitter_ewma * 4.0 * 48.0) as usize)
                .min(4800);
            if !u.primed
                && !u.packets.is_empty()
                && u.queued_at.elapsed()
                    >= Duration::from_micros((target as u64 * 1_000_000) / 48000)
            {
                u.primed = true;
                u.sequence = u.packets.first_key_value().map(|(&seq, _)| seq);
            }
        }
        let frames = frames.min(self.render_buffer.len() / 2);
        self.render_buffer[..frames * 2].fill(0.0);
        for u in self.users.values_mut() {
            if !u.primed {
                continue;
            }
            let mut pcm = [0.0f32; 5760];
            while u.jitter_queue.len() < frames {
                let Some(mut next) = u.sequence else { break };
                // Bound recovery after a long gap rather than manufacturing seconds of PLC.
                if let Some((&seq, _)) = u.packets.first_key_value() {
                    if seq > next + 20 {
                        next = seq;
                        u.sequence = Some(seq);
                    }
                }
                let decoded = if let Some(payload) = u.packets.remove(&next) {
                    u.decoder.decode_float(&payload, &mut pcm, false).ok()
                } else if !u.packets.is_empty()
                    || (u.is_talking && u.last_packet_time.elapsed() < TALKING_TIMEOUT)
                {
                    let size = u.last_frame_samples.min(5760);
                    if let Some((_, payload)) = u
                        .packets
                        .first_key_value()
                        .filter(|(seq, _)| **seq == next + (size / 480) as u64)
                    {
                        u.decoder.decode_float(payload, &mut pcm[..size], true).ok()
                    } else {
                        u.decoder.decode_float(&[], &mut pcm[..size], false).ok()
                    }
                } else {
                    None
                };
                let Some(count) = decoded.filter(|&n| n > 0) else {
                    break;
                };
                u.last_frame_samples = count;
                u.sequence = Some(next + (count / 480).max(1) as u64);
                u.jitter_queue.extend(
                    pcm[..count]
                        .iter()
                        .map(|&s| if s.is_finite() { s } else { 0.0 }),
                );
            }
            for i in 0..frames {
                let Some(sample) = u.jitter_queue.pop_front() else {
                    break;
                };
                for c in 0..2 {
                    self.render_buffer[i * 2 + c] += sample * u.render_gains[c];
                }
            }
            if !u.is_talking && u.packets.is_empty() && u.jitter_queue.is_empty() {
                u.primed = false;
                u.sequence = None;
                u.last_arrival = None;
            }
        }
        for &sample in &self.render_buffer[..frames * 2] {
            let _ = self
                .speaker_producer
                .push(if deafened { 0.0 } else { soft_clip(sample) });
        }
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

        self.users
            .retain(|_, u| now.duration_since(u.last_packet_time) < Duration::from_secs(60));
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

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (AudioMixer, rtrb::Consumer<f32>) {
        let (p, c) = rtrb::RingBuffer::new(20000);
        (AudioMixer::new(p).unwrap(), c)
    }
    fn speaker(id: u32, sample: f32) -> UserAudioState {
        let mut u = UserAudioState::new(id).unwrap();
        u.jitter_queue.extend(std::iter::repeat_n(sample, 960));
        u.primed = true;
        u
    }
    #[test]
    fn overlapping_speakers_are_summed_not_concatenated() {
        let (mut m, mut c) = fixture();
        m.users.insert(1, speaker(1, 0.2));
        m.users.insert(2, speaker(2, 0.3));
        m.render(480, false);
        for _ in 0..960 {
            assert!((c.pop().unwrap() - 0.5).abs() < 1e-6);
        }
        m.render(480, true);
        for _ in 0..960 {
            assert_eq!(c.pop().unwrap(), 0.0);
        }
    }
    #[test]
    fn channel_spatialization_produces_distinct_stereo_channels() {
        let (mut m, mut c) = fixture();
        m.spatial = true;
        m.users.insert(1, speaker(1, 0.5));
        m.render(1, false);
        let l = c.pop().unwrap();
        let r = c.pop().unwrap();
        assert!((l - r).abs() > 0.01);
        assert!(l.is_finite() && r.is_finite());
    }
    #[test]
    fn every_transmission_has_a_terminator_even_at_exact_frame_boundary() {
        let (mut m, _) = fixture();
        let packets = m.push_mic_pcm(&[0.1; 960], 0);
        assert_eq!(packets.len(), 1);
        assert!(m.finish_mic_stream(0).unwrap().is_terminator);
        assert!(m.finish_mic_stream(0).is_none());
    }
    #[test]
    fn jitter_queue_is_bounded_and_duplicates_do_not_add_audio() {
        let (mut m, _) = fixture();
        let mut encoder =
            opus::Encoder::new(48000, opus::Channels::Mono, opus::Application::Voip).unwrap();
        let mut encoded = [0; 1024];
        let len = encoder.encode_float(&[0.2; 960], &mut encoded).unwrap();
        let mut packet = ServerVoicePacket {
            volume_adjustment: 1.0,
            codec: 4,
            target: 0,
            session_id: 1,
            sequence: 0,
            is_terminator: false,
            opus_payload: encoded[..len].to_vec(),
            positional_data: None,
        };
        for seq in 0..100 {
            packet.sequence = seq;
            m.process_incoming_voice(packet.clone(), 1.0, false, false);
        }
        assert!(m.users[&1].packets.len() <= 32);
        let len = m.users[&1].jitter_queue.len();
        m.process_incoming_voice(packet, 1.0, false, false);
        assert_eq!(m.users[&1].jitter_queue.len(), len);
    }
    #[test]
    fn reordered_packets_are_decoded_in_sequence_and_gaps_use_concealment() {
        let (mut mixer, mut output) = fixture();
        let mut encoder =
            opus::Encoder::new(48000, opus::Channels::Mono, opus::Application::Voip).unwrap();
        let mut buffer = [0u8; 1024];
        let size = encoder.encode_float(&[0.2; 960], &mut buffer).unwrap();
        for sequence in [0, 4, 2] {
            mixer.process_incoming_voice(
                ServerVoicePacket {
                    volume_adjustment: 1.0,
                    codec: 4,
                    target: 0,
                    session_id: 1,
                    sequence,
                    is_terminator: false,
                    opus_payload: buffer[..size].to_vec(),
                    positional_data: None,
                },
                1.0,
                false,
                false,
            );
        }
        assert_eq!(
            mixer.users[&1].packets.keys().copied().collect::<Vec<_>>(),
            vec![0, 2, 4]
        );
        let user = mixer.users.get_mut(&1).unwrap();
        user.primed = true;
        user.sequence = Some(0);
        mixer.render(2880, false);
        assert_eq!(mixer.users[&1].sequence, Some(6));
        mixer.render(960, false);
        assert_eq!(mixer.users[&1].sequence, Some(8));
        assert!(output.pop().is_ok());
    }
    #[test]
    fn encoder_respects_server_budget_and_packet_duration() {
        let (mut mixer, _) = fixture();
        mixer.configure_quality(96000, 10, true);
        mixer.set_server_bandwidth(32000);
        assert!(mixer.bitrate() < 32000);
        assert_eq!(mixer.push_mic_pcm(&[0.1; 960], 0).len(), 2);
    }
    #[test]
    fn render_cost_for_ten_simultaneous_speakers() {
        let (mut m, mut c) = fixture();
        m.spatial = true;
        for id in 1..=10 {
            m.users.insert(id, speaker(id, 0.02));
        }
        let start = Instant::now();
        for _ in 0..500 {
            for u in m.users.values_mut() {
                u.jitter_queue.extend(std::iter::repeat_n(0.02, 480));
            }
            m.render(480, false);
            while c.pop().is_ok() {}
        }
        eprintln!(
            "10-speaker stereo mixer: {:?} for 5 seconds of audio",
            start.elapsed()
        );
    }
}

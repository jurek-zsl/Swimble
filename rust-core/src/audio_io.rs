//! CoreAudio boundary: bounded SPSC queues, with no codec, lock, allocation,
//! networking, or file I/O in the exported capture/playback functions.
use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use std::{
    cell::UnsafeCell,
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, Weak,
    },
    time::Duration,
};
const CAPACITY: usize = 8192;
pub struct Capture {
    pub samples: [f32; CAPACITY],
    pub len: usize,
    pub rate: u32,
    pub target: i32,
}
pub struct AudioPort {
    capture: UnsafeCell<rtrb::Producer<Capture>>,
    input: Mutex<rtrb::Consumer<Capture>>,
    output: Mutex<rtrb::Producer<f32>>,
    playback: UnsafeCell<rtrb::Consumer<f32>>,
    capture_busy: AtomicBool,
    playback_busy: AtomicBool,
    pub active: AtomicBool,
    pub overruns: AtomicU64,
    pub underruns: AtomicU64,
    pub metrics: Mutex<crate::AudioMetrics>,
    pub diagnostics: AtomicBool,
    pub loopback: std::sync::atomic::AtomicU32,
    recorder: Mutex<Option<hound::WavWriter<std::io::BufWriter<std::fs::File>>>>,
}
// Each endpoint is used by exactly one hardware callback. Atomic try-guards
// reject accidental concurrent callbacks without waiting or aliasing UnsafeCell.
// Worker endpoints and recording lifetime are serialized independently.
unsafe impl Sync for AudioPort {}
impl AudioPort {
    pub fn new() -> Arc<Self> {
        let (cp, cc) = rtrb::RingBuffer::new(16);
        let (sp, sc) = rtrb::RingBuffer::new(9600 * 2);
        Arc::new(Self {
            capture: UnsafeCell::new(cp),
            input: Mutex::new(cc),
            output: Mutex::new(sp),
            playback: UnsafeCell::new(sc),
            capture_busy: AtomicBool::new(false),
            playback_busy: AtomicBool::new(false),
            active: AtomicBool::new(false),
            overruns: AtomicU64::new(0),
            underruns: AtomicU64::new(0),
            metrics: Mutex::new(crate::AudioMetrics::default()),
            diagnostics: AtomicBool::new(false),
            loopback: std::sync::atomic::AtomicU32::new(0),
            recorder: Mutex::new(None),
        })
    }
    pub fn start_recording(&self, path: String) -> Result<(), hound::Error> {
        let file = hound::WavWriter::create(
            path,
            hound::WavSpec {
                channels: 2,
                sample_rate: 48000,
                bits_per_sample: 16,
                sample_format: hound::SampleFormat::Int,
            },
        )?;
        *self.recorder.lock().unwrap() = Some(file);
        Ok(())
    }
    pub fn stop_recording(&self) {
        if let Some(file) = self.recorder.lock().unwrap().take() {
            let _ = file.finalize();
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn swimble_audio_release(handle: u64) {
    if handle != 0 {
        drop(Arc::from_raw(handle as *const AudioPort));
    }
}
#[no_mangle]
pub unsafe extern "C" fn swimble_audio_active(handle: u64, active: bool) {
    if let Some(p) = (handle as *const AudioPort).as_ref() {
        p.active.store(active, Ordering::Release);
        if !active {
            // Called only after the engine stops. Serialize with the producer
            // before draining old playback, so reconnect cannot replay a tail.
            let _producer = p.output.lock().unwrap();
            if !p.playback_busy.swap(true, Ordering::Acquire) {
                while (&mut *p.playback.get()).pop().is_ok() {}
                p.playback_busy.store(false, Ordering::Release);
            }
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn swimble_audio_capture(
    handle: u64,
    samples: *const f32,
    len: u32,
    rate: u32,
    gain: f32,
    target: i32,
) {
    let Some(p) = (handle as *const AudioPort).as_ref() else {
        return;
    };
    if !p.active.load(Ordering::Acquire)
        || samples.is_null()
        || len == 0
        || len as usize > CAPACITY
        || !(8000..=384000).contains(&rate)
        || !gain.is_finite()
    {
        return;
    }
    if p.capture_busy.swap(true, Ordering::Acquire) {
        p.overruns.fetch_add(1, Ordering::Relaxed);
        return;
    }
    let mut block = Capture {
        samples: [0.0; CAPACITY],
        len: len as usize,
        rate,
        target,
    };
    for (out, &sample) in block.samples[..len as usize]
        .iter_mut()
        .zip(std::slice::from_raw_parts(samples, len as usize))
    {
        *out = if sample.is_finite() {
            (sample * gain).clamp(-1.0, 1.0)
        } else {
            0.0
        };
    }
    if (&mut *p.capture.get()).push(block).is_err() {
        p.overruns.fetch_add(1, Ordering::Relaxed);
    }
    p.capture_busy.store(false, Ordering::Release);
}
#[no_mangle]
pub unsafe extern "C" fn swimble_audio_playback(
    handle: u64,
    left: *mut f32,
    right: *mut f32,
    frames: u32,
    gain: f32,
) {
    if left.is_null() || right.is_null() || frames as usize > CAPACITY {
        return;
    }
    let Some(p) = (handle as *const AudioPort).as_ref() else {
        return;
    };
    if p.playback_busy.swap(true, Ordering::Acquire) {
        std::ptr::write_bytes(left, 0, frames as usize);
        std::ptr::write_bytes(right, 0, frames as usize);
        return;
    }
    let consumer = &mut *p.playback.get();
    let mut missing = false;
    for i in 0..frames as usize {
        let l = consumer.pop().unwrap_or_else(|_| {
            missing = true;
            0.0
        });
        let r = consumer.pop().unwrap_or(0.0);
        *left.add(i) = (l * gain).clamp(-1.0, 1.0);
        *right.add(i) = (r * gain).clamp(-1.0, 1.0);
    }
    if missing {
        p.underruns.fetch_add(1, Ordering::Relaxed);
    }
    p.playback_busy.store(false, Ordering::Release);
}
pub fn start_worker(client: Weak<crate::MumbleClient>) {
    let Some(owner) = client.upgrade() else {
        return;
    };
    owner.runner.spawn(async move {
        let mut source_rate = 48000;
        let mut resampler: Option<SincFixedIn<f32>> = None;
        let mut mic = VecDeque::<f32>::with_capacity(19200);
        let mut tick = tokio::time::interval(Duration::from_millis(5));
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            tick.tick().await;
            let Some(client) = client.upgrade() else {
                break;
            };
            let port = &client.audio_port;
            if !port.active.load(Ordering::Acquire) {
                while port.input.lock().unwrap().pop().is_ok() {}
                mic.clear();
                drop(client);
                tokio::time::sleep(Duration::from_millis(50)).await;
                tick.reset();
                continue;
            }
            loop {
                let block = port.input.lock().unwrap().pop();
                let Ok(block) = block else { break };
                if source_rate != block.rate {
                    source_rate = block.rate;
                    resampler = if source_rate == 48000 {
                        None
                    } else {
                        SincFixedIn::new(
                            48000.0 / source_rate as f64,
                            1.0,
                            SincInterpolationParameters {
                                sinc_len: 128,
                                f_cutoff: 0.95,
                                interpolation: SincInterpolationType::Linear,
                                oversampling_factor: 128,
                                window: WindowFunction::BlackmanHarris2,
                            },
                            CAPACITY,
                            1,
                        )
                        .ok()
                    };
                }
                let converted = if let Some(ref mut converter) = resampler {
                    let _ = converter.set_chunk_size(block.len);
                    converter
                        .process(&[&block.samples[..block.len]], None)
                        .ok()
                        .and_then(|mut channels| channels.pop())
                        .unwrap_or_default()
                } else {
                    block.samples[..block.len].to_vec()
                };
                if mic.len() + converted.len() > 19200 {
                    mic.clear();
                }
                mic.extend(converted.iter().copied());
                let mut metrics = port.metrics.lock().unwrap();
                let rms = (converted.iter().map(|x| x * x).sum::<f32>()
                    / converted.len().max(1) as f32)
                    .sqrt();
                metrics.mic_frames_processed += converted.len() as u64;
                metrics.mic_db = 20.0 * rms.max(1e-5).log10();
                metrics.transmitting = block.target >= 0;
                if port.diagnostics.load(Ordering::Relaxed) {
                    metrics.mic_samples = converted.iter().rev().take(1024).copied().collect();
                }
                drop(metrics);
                let loopback = port.loopback.load(Ordering::Relaxed);
                if loopback == 2 {
                    client.push_mic_pcm(converted, Some(31));
                } else if block.target >= 0 {
                    client.push_mic_pcm(converted, Some(block.target as u8));
                } else {
                    client.finish_mic_stream(None);
                }
            }
            // Hardware consumption sets the sample clock; scheduler jitter never
            // consumes/discards mixer data or extends the recording timeline.
            for _ in 0..4 {
                if port.output.lock().unwrap().slots() < 19200 - 1920 {
                    break;
                }
                let mut speaker = client.pull_speaker_pcm(480);
                let mut recorder = port.recorder.lock().unwrap();
                for (i, frame) in speaker.chunks_exact_mut(2).enumerate() {
                    let local = mic.pop_front().unwrap_or(0.0);
                    if port.loopback.load(Ordering::Relaxed) == 1 {
                        frame[0] += local;
                        frame[1] += local;
                    }
                    if let Some(file) = recorder.as_mut() {
                        let _ = file.write_sample((local.clamp(-1.0, 1.0) * 32767.0) as i16);
                        let _ = file.write_sample(
                            (((frame[0] + frame[1]) * 0.5).clamp(-1.0, 1.0) * 32767.0) as i16,
                        );
                    }
                    let _ = i;
                }
                drop(recorder);
                if port.diagnostics.load(Ordering::Relaxed) {
                    port.metrics.lock().unwrap().speaker_samples = speaker.clone();
                }
                let mut producer = port.output.lock().unwrap();
                if port.active.load(Ordering::Acquire) {
                    for sample in speaker {
                        let _ = producer.push(sample);
                    }
                }
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stateful_resampling_preserves_duration_across_variable_blocks() {
        let mut converter = SincFixedIn::<f32>::new(
            48000.0 / 44100.0,
            1.0,
            SincInterpolationParameters {
                sinc_len: 128,
                f_cutoff: 0.95,
                interpolation: SincInterpolationType::Linear,
                oversampling_factor: 128,
                window: WindowFunction::BlackmanHarris2,
            },
            8192,
            1,
        )
        .unwrap();
        let mut produced = 0;
        for _ in 0..100 {
            converter.set_chunk_size(441).unwrap();
            produced += converter.process(&[vec![0.1; 441]], None).unwrap()[0].len();
        }
        assert!(
            (produced as i64 + converter.output_delay() as i64 - 48000).abs() < 10,
            "Unexpected resampler clock drift: {produced}"
        );
    }
}

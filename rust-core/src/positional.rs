//! Standard POSIX Mumble Link (native wchar_t = 32 bits on macOS/Unix).
//! ABI follows the public-domain integration example at mumble.info.
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub struct LinkFrame {
    pub avatar: [f32; 3],
    pub camera: [f32; 3],
    pub front: [f32; 3],
    pub top: [f32; 3],
    pub context: Vec<u8>,
    pub identity: String,
}

const WORDS: usize = (8 + 36 + 1024 + 36 + 1024 + 4 + 256 + 8192) / 4;
pub struct MumbleLink {
    memory: *mut libc::c_void,
    last_tick: u32,
    changed_at: Instant,
    seen_update: bool,
}
// Only accessed while the AudioMixer mutex is held. The external producer uses
// atomic 32-bit chunks, as does Mumble's native Link implementation.
unsafe impl Send for MumbleLink {}
impl MumbleLink {
    pub fn open() -> Option<Self> {
        #[cfg(unix)]
        {
            let name = std::ffi::CString::new(format!("/MumbleLink.{}", unsafe { libc::getuid() }))
                .ok()?;
            Self::open_named(&name)
        }
        #[cfg(not(unix))]
        {
            None
        }
    }

    #[cfg(unix)]
    fn open_named(name: &std::ffi::CStr) -> Option<Self> {
        unsafe {
            let fd = libc::shm_open(
                name.as_ptr(),
                libc::O_RDWR | libc::O_CREAT | libc::O_EXCL,
                0o600,
            );
            let (fd, created) = if fd >= 0 {
                (fd, true)
            } else {
                (libc::shm_open(name.as_ptr(), libc::O_RDWR, 0o600), false)
            };
            if fd < 0 {
                return None;
            }
            let size = WORDS * 4;
            let mut stat: libc::stat = std::mem::zeroed();
            let valid = if created {
                libc::ftruncate(fd, size as libc::off_t) == 0
            } else {
                libc::fstat(fd, &mut stat) == 0
                    && stat.st_size >= size as i64
                    && stat.st_uid == libc::getuid()
            };
            if !valid {
                libc::close(fd);
                return None;
            }
            let memory = libc::mmap(
                std::ptr::null_mut(),
                size,
                libc::PROT_READ,
                libc::MAP_SHARED,
                fd,
                0,
            );
            libc::close(fd);
            if memory == libc::MAP_FAILED {
                return None;
            }
            let last_tick = (&*memory.cast::<AtomicU32>().add(1)).load(Ordering::Relaxed);
            Some(Self {
                memory,
                last_tick,
                changed_at: Instant::now(),
                seen_update: false,
            })
        }
    }
    pub fn read(&mut self) -> Option<LinkFrame> {
        let mut words = [0u32; WORDS];
        for (i, out) in words.iter_mut().enumerate() {
            // Mapping is page aligned, all offsets are multiples of four, and
            // the length was checked before mapping. No Rust reference aliases writes.
            *out = unsafe { (&*self.memory.cast::<AtomicU32>().add(i)).load(Ordering::Relaxed) };
        }
        let version = words[0];
        if version != 1 && version != 2 {
            return None;
        }
        if words[1] != self.last_tick {
            self.last_tick = words[1];
            self.changed_at = Instant::now();
            self.seen_update = true;
        }
        if !self.seen_update || self.changed_at.elapsed() > Duration::from_secs(2) {
            return None;
        }
        let vector = |offset| {
            [
                f32::from_bits(words[offset]),
                f32::from_bits(words[offset + 1]),
                f32::from_bits(words[offset + 2]),
            ]
        };
        let avatar = vector(2);
        let camera = if version == 2 { vector(267) } else { avatar };
        let front = if version == 2 { vector(270) } else { vector(5) };
        let top = if version == 2 { vector(273) } else { vector(8) };
        if !avatar
            .iter()
            .chain(camera.iter())
            .chain(front.iter())
            .chain(top.iter())
            .all(|x| x.is_finite() && x.abs() < 1e8)
        {
            return None;
        }
        let string = |slice: &[u32]| {
            slice
                .iter()
                .take_while(|&&c| c != 0)
                .filter_map(|&c| char::from_u32(c))
                .collect::<String>()
        };
        let name = string(&words[11..267]);
        let identity = if version == 2 {
            string(&words[276..532])
        } else {
            String::new()
        };
        let mut context = name.into_bytes();
        context.push(0);
        if version == 2 {
            let length = (words[532] as usize).min(256);
            let bytes: Vec<u8> = words[533..597]
                .iter()
                .flat_map(|x| x.to_ne_bytes())
                .collect();
            context.extend_from_slice(&bytes[..length]);
        }
        Some(LinkFrame {
            avatar,
            camera,
            front,
            top,
            context,
            identity,
        })
    }
}
impl Drop for MumbleLink {
    fn drop(&mut self) {
        unsafe {
            libc::munmap(self.memory, WORDS * 4);
        }
    }
}

pub fn gains(position: [f32; 3], listener: &LinkFrame) -> [f32; 2] {
    gains_configured(position, listener, [1.0, 50.0, 0.0, 0.25])
}
pub fn gains_configured(position: [f32; 3], listener: &LinkFrame, settings: [f32; 4]) -> [f32; 2] {
    let d = [
        position[0] - listener.camera[0],
        position[1] - listener.camera[1],
        position[2] - listener.camera[2],
    ];
    let distance = d.iter().map(|x| x * x).sum::<f32>().sqrt();
    let right = [
        listener.top[1] * listener.front[2] - listener.top[2] * listener.front[1],
        listener.top[2] * listener.front[0] - listener.top[0] * listener.front[2],
        listener.top[0] * listener.front[1] - listener.top[1] * listener.front[0],
    ];
    let norm = right.iter().map(|x| x * x).sum::<f32>().sqrt().max(0.001);
    let pan = (d.iter().zip(right).map(|(a, b)| a * b).sum::<f32>() / (distance.max(0.001) * norm))
        .clamp(-1.0, 1.0);
    let [near, far, floor, bloom] = settings;
    let t = ((distance - near) / (far - near).max(0.01)).clamp(0.0, 1.0);
    let attenuation = 1.0 + (floor - 1.0) * t;
    let spread = (distance / near.max(0.01)).clamp(bloom, 1.0);
    stereo_pan(pan * spread).map(|g| g * attenuation)
}
pub fn stereo_pan(pan: f32) -> [f32; 2] {
    let angle = (pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
    [angle.cos(), angle.sin()]
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_link_memory_layout_context_and_stale_tick() {
        let name =
            std::ffi::CString::new(format!("/SwimbleLinkTest.{}", std::process::id())).unwrap();
        let mut reader = MumbleLink::open_named(&name).unwrap();
        assert!(reader.read().is_none());
        unsafe {
            let fd = libc::shm_open(name.as_ptr(), libc::O_RDWR, 0o600);
            assert!(fd >= 0);
            let memory = libc::mmap(
                std::ptr::null_mut(),
                WORDS * 4,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd,
                0,
            );
            libc::close(fd);
            assert_ne!(memory, libc::MAP_FAILED);
            let write = |offset: usize, value| {
                (&*memory.cast::<AtomicU32>().add(offset)).store(value, Ordering::Relaxed)
            };
            write(0, 2);
            write(2, 1.0f32.to_bits());
            write(272, 1.0f32.to_bits());
            write(274, 1.0f32.to_bits());
            for (i, c) in "TestGame".chars().enumerate() {
                write(11 + i, c as u32);
            }
            write(532, 3);
            write(533, u32::from_ne_bytes([1, 2, 3, 0]));
            write(1, 1);
            let frame = reader.read().unwrap();
            assert_eq!(frame.avatar, [1.0, 0.0, 0.0]);
            assert_eq!(frame.front, [0.0, 0.0, 1.0]);
            assert_eq!(frame.context, b"TestGame\0\x01\x02\x03");
            reader.changed_at = Instant::now() - Duration::from_secs(3);
            assert!(reader.read().is_none());
            write(2, f32::NAN.to_bits());
            write(1, 2);
            assert!(reader.read().is_none());
            libc::munmap(memory, WORDS * 4);
            libc::shm_unlink(name.as_ptr());
        }
    }

    #[test]
    fn listener_orientation_and_distance_affect_stereo_gains() {
        let mut listener = LinkFrame {
            avatar: [0.0; 3],
            camera: [0.0; 3],
            front: [0.0, 0.0, 1.0],
            top: [0.0, 1.0, 0.0],
            context: vec![],
            identity: String::new(),
        };
        let right = gains([1.0, 0.0, 0.0], &listener);
        assert!(right[1] > right[0] * 10.0);
        listener.front = [0.0, 0.0, -1.0];
        let left = gains([1.0, 0.0, 0.0], &listener);
        assert!(left[0] > left[1] * 10.0);
        let far = gains([100.0, 0.0, 0.0], &listener);
        assert!(far[0] < left[0] * 0.2);
    }
}

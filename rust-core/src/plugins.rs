use crate::positional::LinkFrame;
use std::ffi::{c_char, c_void, CString};
unsafe extern "C" {
    fn swimble_plugin_open(path: *const c_char) -> *mut c_void;
    fn swimble_plugin_close(host: *mut c_void);
    fn swimble_plugin_fetch(
        host: *mut c_void,
        vectors: *mut f32,
        context: *mut c_char,
        context_cap: usize,
        identity: *mut c_char,
        identity_cap: usize,
    ) -> bool;
}
pub struct PositionalPlugin {
    host: *mut c_void,
    pub path: String,
}
// Plugin callbacks, initialization and destruction are serialized by AudioMixer.
unsafe impl Send for PositionalPlugin {}
impl PositionalPlugin {
    pub fn load(path: String) -> Result<Self, String> {
        let name = CString::new(path.clone()).map_err(|_| "Invalid plugin path")?;
        let host = unsafe { swimble_plugin_open(name.as_ptr()) };
        if host.is_null() {
            Err("Could not load plugin. Use a native macOS legacy positional plugin or a Mumble API 1.2 positional plugin with no required general-host API dependencies.".into())
        } else {
            Ok(Self { host, path })
        }
    }
    pub fn read(&mut self) -> Option<LinkFrame> {
        let mut data = [0.0; 18];
        let mut context = [0u8; 8196];
        let mut identity = [0u8; 8192];
        if !unsafe {
            swimble_plugin_fetch(
                self.host,
                data.as_mut_ptr(),
                context.as_mut_ptr().cast(),
                context.len(),
                identity.as_mut_ptr().cast(),
                identity.len(),
            )
        } {
            return None;
        }
        if !data.iter().all(|x| x.is_finite()) {
            return None;
        }
        let len = u32::from_ne_bytes(context[..4].try_into().ok()?) as usize;
        Some(LinkFrame {
            avatar: data[0..3].try_into().ok()?,
            camera: data[9..12].try_into().ok()?,
            front: data[12..15].try_into().ok()?,
            top: data[15..18].try_into().ok()?,
            context: context[4..4 + len.min(8192)].to_vec(),
            identity: String::from_utf8_lossy(
                &identity[..identity
                    .iter()
                    .position(|&b| b == 0)
                    .unwrap_or(identity.len())],
            )
            .into_owned(),
        })
    }
}
impl Drop for PositionalPlugin {
    fn drop(&mut self) {
        unsafe { swimble_plugin_close(self.host) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_plugin_abi_and_context_are_compatible() {
        let temp = tempfile::tempdir().unwrap();
        let library = temp.path().join(if cfg!(target_os = "macos") {
            "fixture.dylib"
        } else {
            "fixture.so"
        });
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let result = std::process::Command::new("c++")
            .arg("-std=c++17")
            .arg("-shared")
            .arg("-fPIC")
            .arg("-I")
            .arg(root.join("native"))
            .arg(root.join("tests/fixtures/positional_plugin.cpp"))
            .arg("-o")
            .arg(&library)
            .status()
            .unwrap();
        assert!(result.success());
        let mut plugin = PositionalPlugin::load(library.to_str().unwrap().into()).unwrap();
        let data = plugin.read().unwrap();
        assert_eq!(data.avatar, [1.0, 2.0, 3.0]);
        assert_eq!(data.camera, [4.0, 5.0, 6.0]);
        assert_eq!(data.context, b"SharedGame\0world");
        assert_eq!(data.identity, "player");
    }
}

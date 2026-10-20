//! Per-user local control socket. It accepts a fixed command vocabulary only.
use std::{
    collections::VecDeque,
    io::{Read, Write},
    os::unix::{
        fs::{MetadataExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
    sync::{Mutex, OnceLock},
};
static COMMANDS: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());
static STARTED: OnceLock<Result<String, String>> = OnceLock::new();
pub fn socket_path() -> PathBuf {
    std::env::temp_dir()
        .join(format!("swimble-control-{}", unsafe { libc::geteuid() }))
        .join("control.sock")
}
fn valid(command: &str) -> bool {
    match command {
        "mute" | "unmute" | "togglemute" | "deaf" | "undeaf" | "toggledeaf" | "starttalking"
        | "stoptalking" => true,
        _ => command
            .strip_prefix("join ")
            .or_else(|| command.strip_prefix("listen "))
            .is_some_and(|id| id.parse::<u32>().is_ok()),
    }
}
#[uniffi::export]
pub fn start_local_control() -> String {
    STARTED
        .get_or_init(|| {
            let path = socket_path();
            let parent = path.parent().unwrap();
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            let meta = std::fs::symlink_metadata(parent).map_err(|e| e.to_string())?;
            if !meta.is_dir() || meta.uid() != unsafe { libc::geteuid() } {
                return Err("Unsafe local-control directory".into());
            }
            std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))
                .map_err(|e| e.to_string())?;
            if path.exists() {
                if UnixStream::connect(&path).is_ok() {
                    return Err("Another Swimble instance owns local control".into());
                }
                std::fs::remove_file(&path).map_err(|e| e.to_string())?;
            }
            let listener = UnixListener::bind(&path).map_err(|e| e.to_string())?;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))
                .map_err(|e| e.to_string())?;
            std::thread::Builder::new()
                .name("Swimble local control".into())
                .spawn(move || {
                    for mut stream in listener.incoming().flatten() {
                        let _ =
                            stream.set_read_timeout(Some(std::time::Duration::from_millis(200)));
                        let mut bytes = [0u8; 1024];
                        let n = stream.read(&mut bytes).unwrap_or(0);
                        let command = String::from_utf8_lossy(&bytes[..n]).trim().to_string();
                        let mut queue = COMMANDS.lock().unwrap();
                        let reply = if valid(&command) && queue.len() < 64 {
                            queue.push_back(command);
                            "queued\n"
                        } else {
                            "invalid command or queue full\n"
                        };
                        let _ = stream.write_all(reply.as_bytes());
                    }
                })
                .map_err(|e| e.to_string())?;
            Ok(path.display().to_string())
        })
        .clone()
        .unwrap_or_else(|e| format!("Unavailable: {e}"))
}
#[uniffi::export]
pub fn take_local_commands() -> Vec<String> {
    COMMANDS.lock().unwrap().drain(..).collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn commands_are_not_arbitrary_shell_input() {
        assert!(valid("mute"));
        assert!(valid("join 123"));
        assert!(!valid("join -1"));
        assert!(!valid("mute; touch /tmp/file"));
        assert!(!valid("eval code"));
    }
}

#[cfg(test)]
mod socket_tests {
    use super::*;
    #[test]
    fn local_control_socket_is_private_and_rejects_unknown_commands() {
        let status = start_local_control();
        // A separately running app owns its own socket; do not alter it.
        if status.starts_with("Unavailable:") {
            return;
        }
        assert_eq!(
            std::fs::metadata(socket_path())
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        let mut socket = UnixStream::connect(socket_path()).unwrap();
        socket
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        socket.write_all(b"not-a-command").unwrap();
        let mut reply = String::new();
        socket.read_to_string(&mut reply).unwrap();
        assert!(reply.starts_with("invalid"));
        let mut socket = UnixStream::connect(socket_path()).unwrap();
        socket
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        socket.write_all(b"mute").unwrap();
        let mut reply = String::new();
        socket.read_to_string(&mut reply).unwrap();
        assert_eq!(reply, "queued\n");
        assert_eq!(take_local_commands(), vec!["mute"]);
        std::fs::remove_file(socket_path()).unwrap();
    }
}

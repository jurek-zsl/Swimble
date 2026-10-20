use std::io::{Read, Write};
fn main() {
    let command = std::env::args().skip(1).collect::<Vec<_>>().join(" ");
    if command.is_empty() || command == "--help" {
        println!("swimble-rpc mute|unmute|togglemute|deaf|undeaf|toggledeaf|starttalking|stoptalking|join CHANNEL_ID|listen CHANNEL_ID");
        return;
    }
    let result = (|| -> std::io::Result<()> {
        let mut stream = std::os::unix::net::UnixStream::connect(mumble_core::rpc::socket_path())?;
        stream.set_read_timeout(Some(std::time::Duration::from_secs(2)))?;
        stream.write_all(command.as_bytes())?;
        let mut response = String::new();
        stream.read_to_string(&mut response)?;
        print!("{response}");
        if response.trim() != "queued" {
            return Err(std::io::Error::other("Command rejected"));
        }
        Ok(())
    })();
    if let Err(error) = result {
        eprintln!("Swimble control: {error}. Start Swimble first.");
        std::process::exit(1);
    }
}

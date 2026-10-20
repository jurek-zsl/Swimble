fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-changed=proto/Mumble.proto");
    println!("cargo:rerun-if-changed=proto/MumbleUDP.proto");
    prost_build::compile_protos(
        &["proto/Mumble.proto", "proto/MumbleUDP.proto"],
        &["proto/"],
    )?;
    println!("cargo:rerun-if-changed=native/plugin_host.cpp");
    println!("cargo:rerun-if-changed=native/MumblePlugin.h");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .file("native/plugin_host.cpp")
        .compile("swimble_plugins");
    Ok(())
}

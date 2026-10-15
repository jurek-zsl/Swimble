fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-changed=proto/Mumble.proto");
    prost_build::compile_protos(&["proto/Mumble.proto"], &["proto/"])?;
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .out_dir("src/generated")
        .compile_protos(&["proto/spans.proto"], &["proto"])?;
    Ok(())
}

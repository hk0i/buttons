fn main() {
    // buttons.proto and wire.proto share proto package `buttons` (one
    // schema split across files, idiomatic proto — see
    // docs/slices/07. Discovery, Pairing & Config Sync.spec.md Scope → In
    // item 2), so prost_build emits one generated file for both, wrapped
    // in a single `buttons` module in src/proto.rs.
    let out_dir = std::env::var("OUT_DIR").unwrap();
    let descriptor_path = std::path::PathBuf::from(&out_dir).join("buttons_descriptor.bin");

    let mut config = prost_build::Config::new();
    config.file_descriptor_set_path(&descriptor_path);
    config
        .compile_protos(
            &["../../protocol/wire.proto"],
            &["../../protocol"],
        )
        .unwrap();

    let descriptor_set = std::fs::read(&descriptor_path).unwrap();
    pbjson_build::Builder::new()
        .register_descriptors(&descriptor_set)
        .unwrap()
        .build(&[".buttons"])
        .unwrap();

    tauri_build::build();
}

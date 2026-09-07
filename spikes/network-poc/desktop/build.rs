fn main() {
    prost_build::compile_protos(&["../proto/ping.proto"], &["../proto"]).unwrap();
}

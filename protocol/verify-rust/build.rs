fn main() {
    prost_build::compile_protos(&["../buttons.proto"], &[".."]).unwrap();
}

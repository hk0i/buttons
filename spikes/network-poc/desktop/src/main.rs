mod ping {
    include!(concat!(env!("OUT_DIR"), "/_.rs"));
}

fn main() {
    let ping = ping::Ping {
        text: "codegen check".to_string(),
    };
    println!("{:?}", ping);
}

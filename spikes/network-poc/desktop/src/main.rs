use std::collections::HashMap;

use mdns_sd::{ServiceDaemon, ServiceInfo};

mod ping {
    include!(concat!(env!("OUT_DIR"), "/_.rs"));
}

const SERVICE_TYPE: &str = "_streamdeck._tcp.local.";
const INSTANCE_NAME: &str = "network-poc-desktop";
const PORT: u16 = 8765;

#[tokio::main]
async fn main() {
    let mdns = ServiceDaemon::new().expect("failed to create mDNS daemon");

    let host_name = format!("{INSTANCE_NAME}.local.");
    let service_info = ServiceInfo::new(
        SERVICE_TYPE,
        INSTANCE_NAME,
        &host_name,
        "",
        PORT,
        None::<HashMap<String, String>>,
    )
    .expect("valid service info")
    .enable_addr_auto();

    mdns.register(service_info)
        .expect("failed to register mDNS service");

    println!("Advertising {INSTANCE_NAME}.{SERVICE_TYPE} on port {PORT} — waiting for Ctrl+C");

    tokio::signal::ctrl_c()
        .await
        .expect("failed to listen for ctrl_c");

    println!("Shutting down mDNS advertisement...");
    mdns.shutdown().expect("failed to shut down mDNS daemon");
}

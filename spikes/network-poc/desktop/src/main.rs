use std::collections::HashMap;
use std::net::{IpAddr, UdpSocket};

use mdns_sd::{ServiceDaemon, ServiceInfo};
use qrcode::render::unicode;
use qrcode::QrCode;

mod ping {
    include!(concat!(env!("OUT_DIR"), "/_.rs"));
}

const SERVICE_TYPE: &str = "_buttonspoc._tcp.local.";
const INSTANCE_NAME: &str = "network-poc-desktop";
const PORT: u16 = 8765;

/// Finds this machine's LAN-facing IP by asking the OS how it would route to
/// an external address — no packets are actually sent.
fn local_ip() -> IpAddr {
    let socket = UdpSocket::bind("0.0.0.0:0").expect("failed to bind UDP socket");
    socket
        .connect("8.8.8.8:80")
        .expect("failed to resolve local route");
    socket
        .local_addr()
        .expect("failed to read local address")
        .ip()
}

fn print_pairing_qr(device_id: &str, ip: IpAddr, port: u16) {
    let payload = format!("{device_id} {ip}:{port}");
    let code = QrCode::new(payload.as_bytes()).expect("failed to encode QR payload");
    let image = code
        .render::<unicode::Dense1x2>()
        .quiet_zone(false)
        .build();
    println!("{payload}\n{image}");
}

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

    println!("Advertising {INSTANCE_NAME}.{SERVICE_TYPE} on port {PORT}");

    print_pairing_qr(INSTANCE_NAME, local_ip(), PORT);

    println!("Waiting for Ctrl+C");

    tokio::signal::ctrl_c()
        .await
        .expect("failed to listen for ctrl_c");

    println!("Shutting down mDNS advertisement...");
    mdns.shutdown().expect("failed to shut down mDNS daemon");
}

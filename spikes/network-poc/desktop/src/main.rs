use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr, UdpSocket};

use futures_util::SinkExt;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use prost::Message as _;
use qrcode::render::unicode;
use qrcode::QrCode;
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::tungstenite::Message;

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

async fn handle_connection(stream: TcpStream, addr: SocketAddr) {
    let mut ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(err) => {
            eprintln!("WebSocket handshake with {addr} failed: {err}");
            return;
        }
    };
    println!("Client connected: {addr}");

    let ping = ping::Ping {
        text: "Hello from Buttons desktop POC".to_string(),
    };
    if let Err(err) = ws_stream
        .send(Message::Binary(ping.encode_to_vec().into()))
        .await
    {
        eprintln!("Failed to send Ping to {addr}: {err}");
        return;
    }
    println!("Sent Ping to {addr}: {ping:?}");
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

    let listener = TcpListener::bind(("0.0.0.0", PORT))
        .await
        .expect("failed to bind WebSocket listener");
    println!("WebSocket server listening on port {PORT} — waiting for Ctrl+C");

    let accept_loop = async {
        loop {
            match listener.accept().await {
                Ok((stream, addr)) => {
                    tokio::spawn(handle_connection(stream, addr));
                }
                Err(err) => eprintln!("Failed to accept connection: {err}"),
            }
        }
    };

    tokio::select! {
        () = accept_loop => {}
        result = tokio::signal::ctrl_c() => {
            result.expect("failed to listen for ctrl_c");
        }
    }

    println!("Shutting down mDNS advertisement...");
    mdns.shutdown().expect("failed to shut down mDNS daemon");
}

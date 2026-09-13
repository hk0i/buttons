//! mDNS advertise + WebSocket accept loop + per-connection pairing
//! handshake + single-active-connection guard. See
//! docs/slices/07. Discovery, Pairing & Config Sync.spec.md, § Scope, and
//! § Implementation Notes, "Single-connection slot is
//! `Mutex<Option<ConnectionHandle>>`."

use crate::config;
use crate::pairing::{self, Pairing};
use crate::proto::buttons;
use futures_util::{SinkExt, StreamExt};
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{oneshot, Mutex};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

const SERVICE_TYPE: &str = "_buttons._tcp.local.";
const INSTANCE_NAME: &str = "buttons-desktop";
// Fixed, arbitrary — no port-conflict handling this slice (Scope → Out
// doesn't mention it; revisit if a real collision ever shows up).
pub const PORT: u16 = 47821;

/// Finds this machine's LAN-facing IP by asking the OS how it would route
/// to an external address — no packets actually sent. Same trick as the
/// network-poc spike (`spikes/network-poc/desktop/src/main.rs`).
pub fn local_ip() -> IpAddr {
    let socket = UdpSocket::bind("0.0.0.0:0").expect("failed to bind UDP socket");
    socket
        .connect("8.8.8.8:80")
        .expect("failed to resolve local route");
    socket
        .local_addr()
        .expect("failed to read local address")
        .ip()
}

struct ConnectionHandle {
    evict_tx: oneshot::Sender<()>,
}

/// `Mutex<Option<ConnectionHandle>>`, not a boolean — see Implementation
/// Notes #9 for why occupancy alone can't be the gate (half-open ghosts
/// from a backgrounded/killed phone) and why eviction is still safe (only
/// a valid-token connection can evict).
type ConnSlot = Arc<Mutex<Option<ConnectionHandle>>>;

/// Advertises mDNS, binds the WebSocket listener, and runs the accept loop
/// forever. Spawned as a background task from Tauri's `.setup()` hook.
pub async fn run(pairing: Arc<Pairing>, config_path: PathBuf) {
    let device_id = pairing.device_id();

    let mdns = ServiceDaemon::new().expect("failed to create mDNS daemon");
    let host_name = format!("{INSTANCE_NAME}.local.");
    let mut txt = HashMap::new();
    txt.insert("device_id".to_string(), device_id);
    let service_info = ServiceInfo::new(SERVICE_TYPE, INSTANCE_NAME, &host_name, "", PORT, Some(txt))
        .expect("valid mDNS service info")
        .enable_addr_auto();
    mdns.register(service_info)
        .expect("failed to register mDNS service");

    let listener = TcpListener::bind(("0.0.0.0", PORT))
        .await
        .expect("failed to bind WebSocket listener");

    let slot: ConnSlot = Arc::new(Mutex::new(None));

    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                tokio::spawn(handle_connection(
                    stream,
                    addr,
                    Arc::clone(&pairing),
                    config_path.clone(),
                    Arc::clone(&slot),
                ));
            }
            Err(e) => eprintln!("server: failed to accept connection: {e}"),
        }
    }
}

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    pairing: Arc<Pairing>,
    config_path: PathBuf,
    slot: ConnSlot,
) {
    let mut ws = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("server: WebSocket handshake with {addr} failed: {e}");
            return;
        }
    };

    let auth_token = match authenticate(&mut ws, &pairing).await {
        Ok(token) => token,
        Err(reason) => {
            let _ = send_envelope(
                &mut ws,
                buttons::Envelope {
                    protocol_version: pairing::PROTOCOL_VERSION.to_string(),
                    message: Some(buttons::envelope::Message::PairResponse(
                        buttons::PairResponse {
                            ok: false,
                            auth_token: None,
                            error: Some(reason),
                        },
                    )),
                },
            )
            .await;
            let _ = ws.close(None).await;
            return;
        }
    };

    if send_envelope(
        &mut ws,
        buttons::Envelope {
            protocol_version: pairing::PROTOCOL_VERSION.to_string(),
            message: Some(buttons::envelope::Message::PairResponse(
                buttons::PairResponse {
                    ok: true,
                    auth_token: Some(auth_token),
                    error: None,
                },
            )),
        },
    )
    .await
    .is_err()
    {
        return;
    }

    // Evict whatever the slot currently holds only *after* this connection
    // authenticated — an unauthenticated attempt never reaches this point,
    // so it can never knock the real device off. See slice 07 spec, §
    // Implementation Notes, "Single-connection slot is
    // `Mutex<Option<ConnectionHandle>>`," and § Definition of Done, "An
    // unauthenticated connection attempt ... does not disrupt that
    // session" (verified via `websocat`, protocol/PAIRING.md).
    let (evict_tx, mut evict_rx) = oneshot::channel();
    {
        let mut guard = slot.lock().await;
        if let Some(old) = guard.take() {
            // The only slot-occupancy log line that exists — deliberately
            // placed here, not at the top of handle_connection, so its
            // absence during a failed authenticate() attempt is itself the
            // evidence DoD 11 checks for (see PAIRING.md's websocat
            // procedure).
            eprintln!("server: evicting previous connection to authenticate {addr}");
            let _ = old.evict_tx.send(());
        }
        *guard = Some(ConnectionHandle { evict_tx });
        println!("server: {addr} authenticated, holding the connection slot");
    }

    let config = match config::load_config(&config_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("server: failed to load config for {addr}: {e}");
            return;
        }
    };
    if send_envelope(
        &mut ws,
        buttons::Envelope {
            protocol_version: pairing::PROTOCOL_VERSION.to_string(),
            message: Some(buttons::envelope::Message::ConfigSync(
                buttons::ConfigSync {
                    config: Some(buttons::Config::from(&config)),
                },
            )),
        },
    )
    .await
    .is_err()
    {
        return;
    }

    // button_press/profile_switch etc. (steps 8-10) aren't designed yet —
    // this slice just holds the connection open until evicted or closed.
    loop {
        tokio::select! {
            msg = ws.next() => match msg {
                Some(Ok(Message::Close(_))) | None => break,
                Some(Ok(_)) => {} // no other message types handled this slice
                Some(Err(e)) => {
                    eprintln!("server: WebSocket error from {addr}: {e}");
                    break;
                }
            },
            _ = &mut evict_rx => {
                let _ = ws.close(None).await;
                break;
            }
        }
    }
}

/// Reads exactly one `Envelope` off the socket, checks `protocol_version`,
/// and runs it through `Pairing::validate` — the single code path for both
/// first-pair and reconnect. See slice 07 spec, § Implementation Notes,
/// "One validator, two acceptable tokens" and "`protocol_version` is
/// checked, not just carried."
async fn authenticate(
    ws: &mut WebSocketStream<TcpStream>,
    pairing: &Pairing,
) -> Result<String, String> {
    let text = match ws.next().await {
        Some(Ok(Message::Text(text))) => text,
        Some(Ok(_)) => return Err("expected a text PairRequest frame".to_string()),
        Some(Err(e)) => return Err(e.to_string()),
        None => return Err("connection closed before pairing".to_string()),
    };

    let envelope: buttons::Envelope =
        serde_json::from_str(&text).map_err(|e| format!("malformed Envelope: {e}"))?;

    if !pairing::check_protocol_version(&envelope.protocol_version) {
        return Err("protocol version mismatch".to_string());
    }

    let pair_request = match envelope.message {
        Some(buttons::envelope::Message::PairRequest(pr)) => pr,
        _ => return Err("expected PairRequest".to_string()),
    };

    pairing
        .validate(&pair_request.token)
        .ok_or_else(|| "invalid or expired token".to_string())
}

async fn send_envelope(
    ws: &mut WebSocketStream<TcpStream>,
    envelope: buttons::Envelope,
) -> Result<(), ()> {
    let text = serde_json::to_string(&envelope).map_err(|_| ())?;
    ws.send(Message::Text(text.into())).await.map_err(|_| ())
}

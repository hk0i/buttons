//! mDNS advertise + WebSocket accept loop + per-connection pairing
//! handshake + single-active-connection guard. See
//! docs/slices/07. Discovery, Pairing & Config Sync.spec.md, § Scope, and
//! § Implementation Notes, "Single-connection slot is
//! `Mutex<Option<ConnectionHandle>>`."

use crate::actions;
use crate::config;
use crate::pairing::{self, Pairing};
use crate::proto::buttons;
use crate::switch_state::{self, SwitchStates};
use chrono::Local;
use futures_util::{SinkExt, StreamExt};
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr, UdpSocket};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tauri::Emitter;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, oneshot, Mutex};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

/// Local wall-clock time, `HH:MM:SS.mmm` — the console's own lines
/// otherwise carry no ordering signal at all. Wall clock, not elapsed-
/// since-launch, so it reads like a normal log timestamp and stays
/// meaningful (and boundedly-sized) across a long-running `tauri dev`
/// session instead of growing into an ever-larger, contextless count.
fn log_time() -> String {
    Local::now().format("%H:%M:%S%.3f").to_string()
}

/// Mirrors wire.proto's `StateChange`, kept as a plain struct here rather
/// than passing the generated `buttons::StateChange` through the channel —
/// server logic stays decoupled from the wire type until `state_push_envelope`
/// converts at the point of sending. See slice 09a spec, § Interface,
/// "Desktop-side signatures."
#[derive(Clone)]
pub struct StateChange {
    pub button_id: String,
    pub is_active: bool,
}

/// Broadcast, not unicast — v1 has one connection, and broadcast needs no
/// rework once that's no longer true. Sent as one `Vec<StateChange>` per
/// broadcast, not one `StateChange` sent N times, so a batch of changes
/// that happened together can never be torn apart by an unrelated
/// broadcast interleaving on a lagging receiver. See slice 09a spec, §
/// Interface Notes 1-2.
pub type StatePushTx = broadcast::Sender<Vec<StateChange>>;

/// Signal-only — `Config` is always re-read fresh at send time. See slice
/// 09c spec, § Interface Note 1.
pub type ConfigChangedTx = broadcast::Sender<()>;

/// Fired after any successful flip (a real `ButtonPress` here, or the
/// editor's `Test` button in `lib.rs` — both go through `execute_press`),
/// carrying the full current map. Desktop's own preview grid
/// (`switchStates.svelte.ts`) is this event's only listener this slice —
/// see slice 09 spec, § Files to Touch #8-9.
const SWITCH_STATES_CHANGED_EVENT: &str = "switch-states-changed";

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
pub async fn run(
    pairing: Arc<Pairing>,
    config_path: PathBuf,
    switch_state_path: PathBuf,
    switch_states: SwitchStates,
    state_push_tx: StatePushTx,
    config_changed_tx: ConfigChangedTx,
    app: tauri::AppHandle,
) {
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
                    switch_state_path.clone(),
                    Arc::clone(&switch_states),
                    state_push_tx.clone(),
                    config_changed_tx.clone(),
                    app.clone(),
                    Arc::clone(&slot),
                ));
            }
            Err(e) => eprintln!("[{}] server: failed to accept connection: {e}", log_time()),
        }
    }
}

async fn handle_connection(
    stream: TcpStream,
    addr: SocketAddr,
    pairing: Arc<Pairing>,
    config_path: PathBuf,
    switch_state_path: PathBuf,
    switch_states: SwitchStates,
    state_push_tx: StatePushTx,
    config_changed_tx: ConfigChangedTx,
    app: tauri::AppHandle,
    slot: ConnSlot,
) {
    let mut ws = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            eprintln!("[{}] server: WebSocket handshake with {addr} failed: {e}", log_time());
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
            eprintln!("[{}] server: evicting previous connection to authenticate {addr}", log_time());
            let _ = old.evict_tx.send(());
        }
        *guard = Some(ConnectionHandle { evict_tx });
        // eprintln!, not println! — sharing one stream with the eviction
        // line right above keeps the pair in true order; stdout/stderr are
        // independently buffered, so mixing them let a "authenticated" and
        // "evicting" pair from the same connection print out of sequence
        // in a merged terminal view (harmless, but confusing to read).
        eprintln!("[{}] server: {addr} authenticated, holding the connection slot", log_time());
    }

    if build_and_send_config_sync(&mut ws, &config_path, &switch_states)
        .await
        .is_err()
    {
        return;
    }

    // profile_switch (step 10) isn't designed yet — this loop only handles
    // ButtonPress as a client-initiated message.
    let mut state_push_rx = state_push_tx.subscribe();
    let mut config_changed_rx = config_changed_tx.subscribe();

    loop {
        tokio::select! {
            msg = ws.next() => match msg {
                Some(Ok(Message::Close(_))) | None => break,
                Some(Ok(Message::Text(text))) => {
                    if let Some(result) = handle_button_press(
                        &text,
                        &config_path,
                        &switch_state_path,
                        &switch_states,
                        &state_push_tx,
                        &app,
                    )
                    .await
                    {
                        if send_envelope(&mut ws, result).await.is_err() {
                            break;
                        }
                    }
                }
                // no other frame types handled this slice
                Some(Ok(_)) => {}
                Some(Err(e)) => {
                    eprintln!("[{}] server: WebSocket error from {addr}: {e}", log_time());
                    break;
                }
            },
            _ = &mut evict_rx => {
                let _ = ws.close(None).await;
                break;
            }
            // A lagging receiver drops old batches rather than blocking the
            // sender — acceptable for a UI-refresh signal that's about to
            // be superseded by whatever state is current anyway. See
            // slice 09a spec, § Implementation Notes 1.
            changes = state_push_rx.recv() => match changes {
                Ok(changes) => {
                    if send_envelope(&mut ws, state_push_envelope(changes)).await.is_err() {
                        break;
                    }
                }
                Err(broadcast::error::RecvError::Lagged(_)) => {}
                // sender outlives the app; unreachable in practice
                Err(broadcast::error::RecvError::Closed) => {}
            },
            // Lagged still resyncs here, unlike state_push_rx above — see
            // slice 09c spec, § Implementation Notes #8.
            config_changed = config_changed_rx.recv() => match config_changed {
                // Load: transient, keep connection. Send: dead socket, break.
                Ok(()) => {
                    if let Err(ConfigSyncSendError::Send) =
                        build_and_send_config_sync(&mut ws, &config_path, &switch_states).await
                    {
                        break;
                    }
                }
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    if let Err(ConfigSyncSendError::Send) =
                        build_and_send_config_sync(&mut ws, &config_path, &switch_states).await
                    {
                        break;
                    }
                }
                // sender outlives the app; unreachable in practice
                Err(broadcast::error::RecvError::Closed) => {}
            }
        }
    }
}

/// Load: transient, log-and-continue. Send: dead socket, break. See slice
/// 09c spec, § Implementation Notes #9.
enum ConfigSyncSendError {
    Load,
    Send,
}

/// The one place a `config_sync` gets built and sent — connect-time and a
/// live resync both call this. See slice 09c spec, § Interface Note 2.
async fn build_and_send_config_sync(
    ws: &mut WebSocketStream<TcpStream>,
    config_path: &Path,
    switch_states: &SwitchStates,
) -> Result<(), ConfigSyncSendError> {
    let config = match config::load_config(config_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[{}] server: failed to load config: {e}", log_time());
            return Err(ConfigSyncSendError::Load);
        }
    };
    let mut wire_config = buttons::Config::from(&config);
    // Merge-at-send-time, not baked into `From` — a reconnecting mobile
    // client sees the real current Switch states immediately, not a
    // hardcoded default. See slice 09 spec, § Interface Note 6.
    crate::proto::apply_switch_states(&mut wire_config, switch_states);
    send_envelope(
        ws,
        buttons::Envelope {
            protocol_version: pairing::PROTOCOL_VERSION.to_string(),
            message: Some(buttons::envelope::Message::ConfigSync(
                buttons::ConfigSync {
                    config: Some(wire_config),
                },
            )),
        },
    )
    .await
    .map_err(|_| ConfigSyncSendError::Send)
}

fn state_push_envelope(changes: Vec<StateChange>) -> buttons::Envelope {
    buttons::Envelope {
        protocol_version: pairing::PROTOCOL_VERSION.to_string(),
        message: Some(buttons::envelope::Message::StatePush(buttons::StatePush {
            changes: changes
                .into_iter()
                .map(|c| buttons::StateChange {
                    button_id: c.button_id,
                    is_active: c.is_active,
                })
                .collect(),
        })),
    }
}

/// Parses one incoming text frame as an `Envelope` and, if it's a
/// `ButtonPress`, runs it through `execute_press` and returns the
/// `ActionResult` envelope to send back. Anything else this slice
/// (malformed JSON, an unexpected variant) is logged and dropped — no
/// reply, same as an unhandled frame type above. See slice 08 spec, §
/// Implementation Notes.
async fn handle_button_press(
    text: &str,
    config_path: &Path,
    switch_state_path: &Path,
    switch_states: &SwitchStates,
    state_push_tx: &StatePushTx,
    app: &tauri::AppHandle,
) -> Option<buttons::Envelope> {
    let envelope: buttons::Envelope = match serde_json::from_str(text) {
        Ok(envelope) => envelope,
        Err(parse_error) => {
            eprintln!("[{}] server: malformed Envelope: {parse_error}", log_time());
            return None;
        }
    };
    let Some(buttons::envelope::Message::ButtonPress(press)) = envelope.message else {
        // no other client-initiated message this slice
        return None;
    };

    let result = execute_press(
        &press.button_id,
        config_path,
        switch_state_path,
        switch_states,
        state_push_tx,
        app,
    )
    .await;
    Some(action_result(&press.button_id, result))
}

/// What pressing `button_id` does, right now — the one function a real
/// `ButtonPress` (above) and the editor's `Test` button (`lib.rs`'s
/// `test_button` command) both call, so there is exactly one definition
/// of "what pressing this button does." See slice 09 spec, § Interface
/// Note 3.
///
/// Loads `Config` fresh (not a connect-time snapshot — an edit made on
/// desktop must be visible to the very next press), runs the current
/// target's actions off the async runtime (`actions::run` is blocking:
/// Enigo, `Command::spawn`), and — only on success, and only for a
/// Switch — records the flip and broadcasts the updated map to
/// `SWITCH_STATES_CHANGED_EVENT`'s listeners.
pub async fn execute_press(
    button_id: &str,
    config_path: &Path,
    switch_state_path: &Path,
    switch_states: &SwitchStates,
    state_push_tx: &StatePushTx,
    app: &tauri::AppHandle,
) -> Result<(), String> {
    let config = config::load_config(config_path)?;

    let current_states = switch_states.lock().unwrap().clone();
    let Some(target) = config.press_target(button_id, &current_states) else {
        return Err("unknown button id".to_string());
    };
    // Cloned to move into spawn_blocking — `target.actions` borrows from
    // `config`, which doesn't outlive this function.
    let actions = target.actions.to_vec();
    let flips_to = target.flips_to;

    let result = tokio::task::spawn_blocking(move || actions::run(&actions))
        .await
        .unwrap_or_else(|join_error| Err(format!("action task panicked: {join_error}")));

    if result.is_ok() {
        if let Some(new_value) = flips_to {
            switch_state::flip_and_save(
                switch_state_path,
                switch_states,
                button_id,
                new_value,
                state_push_tx,
            );
            let snapshot = switch_states.lock().unwrap().clone();
            if let Err(e) = app.emit(SWITCH_STATES_CHANGED_EVENT, snapshot) {
                eprintln!("[{}] server: failed to emit {SWITCH_STATES_CHANGED_EVENT}: {e}", log_time());
            }
        }
    }

    result
}

fn action_result(button_id: &str, result: Result<(), String>) -> buttons::Envelope {
    let (ok, error) = match result {
        Ok(()) => (true, None),
        Err(e) => (false, Some(e)),
    };
    buttons::Envelope {
        protocol_version: pairing::PROTOCOL_VERSION.to_string(),
        message: Some(buttons::envelope::Message::ActionResult(
            buttons::ActionResult {
                button_id: button_id.to_string(),
                ok,
                error,
            },
        )),
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

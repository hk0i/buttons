use crate::config::{Action, MediaKeyKind};
use enigo::{Direction, Enigo, Key, Keyboard, Settings};
use std::process::Command;

/// Tier 1 action execution: launch app/script, hotkey simulation, media key
/// control. Plain Rust, no Tauri types — keeps this reusable regardless of
/// the UI layer (see slice 3 spec's Tauri-agnostic-core note).
pub fn run(actions: &[Action]) -> Result<(), String> {
    // Run every action even if an earlier one fails — a multi-action button
    // (PRD: "one press starts the stream, switches scene, unmutes the mic")
    // shouldn't have step 3 silently skipped because step 2 errored.
    let errors: Vec<String> = actions
        .iter()
        .filter_map(|action| run_one(action).err())
        .collect();

    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("; "))
    }
}

fn run_one(action: &Action) -> Result<(), String> {
    match action {
        Action::LaunchApp { path } => launch_app(path),
        Action::Hotkey { keys } => press_hotkey(keys),
        Action::MediaKey { key } => press_media_key(key),
    }
}

fn launch_app(path: &str) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let result = Command::new("open").arg(path).spawn();

    #[cfg(target_os = "windows")]
    let result = Command::new("cmd").args(["/C", "start", "", path]).spawn();

    #[cfg(target_os = "linux")]
    let result = Command::new(path).spawn();

    result.map(|_| ()).map_err(|e| e.to_string())
}

fn press_hotkey(keys: &[String]) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| e.to_string())?;
    let parsed = keys
        .iter()
        .map(|k| parse_key(k))
        .collect::<Result<Vec<Key>, String>>()?;

    for key in &parsed {
        enigo.key(*key, Direction::Press).map_err(|e| e.to_string())?;
    }
    for key in parsed.iter().rev() {
        enigo.key(*key, Direction::Release).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn press_media_key(key: &MediaKeyKind) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| e.to_string())?;
    let key = match key {
        MediaKeyKind::PlayPause => Key::MediaPlayPause,
        MediaKeyKind::Mute => Key::VolumeMute,
        MediaKeyKind::NextTrack => Key::MediaNextTrack,
        MediaKeyKind::PreviousTrack => Key::MediaPrevTrack,
    };
    enigo.key(key, Direction::Click).map_err(|e| e.to_string())
}

fn parse_key(name: &str) -> Result<Key, String> {
    match name.to_lowercase().as_str() {
        "cmd" | "command" | "meta" | "win" | "windows" => Ok(Key::Meta),
        "shift" => Ok(Key::Shift),
        "ctrl" | "control" => Ok(Key::Control),
        "alt" | "option" => Ok(Key::Alt),
        "space" => Ok(Key::Space),
        "enter" | "return" => Ok(Key::Return),
        "tab" => Ok(Key::Tab),
        "escape" | "esc" => Ok(Key::Escape),
        "backspace" => Ok(Key::Backspace),
        "delete" => Ok(Key::Delete),
        "up" => Ok(Key::UpArrow),
        "down" => Ok(Key::DownArrow),
        "left" => Ok(Key::LeftArrow),
        "right" => Ok(Key::RightArrow),
        "f1" => Ok(Key::F1),
        "f2" => Ok(Key::F2),
        "f3" => Ok(Key::F3),
        "f4" => Ok(Key::F4),
        "f5" => Ok(Key::F5),
        "f6" => Ok(Key::F6),
        "f7" => Ok(Key::F7),
        "f8" => Ok(Key::F8),
        "f9" => Ok(Key::F9),
        "f10" => Ok(Key::F10),
        "f11" => Ok(Key::F11),
        "f12" => Ok(Key::F12),
        "f13" => Ok(Key::F13),
        "f14" => Ok(Key::F14),
        "f15" => Ok(Key::F15),
        "f16" => Ok(Key::F16),
        "f17" => Ok(Key::F17),
        "f18" => Ok(Key::F18),
        "f19" => Ok(Key::F19),
        "f20" => Ok(Key::F20),
        // enigo doesn't define F21-F24 on macOS at all (keycodes.rs gates them
        // to Windows/Linux only) — likely a real macOS CGKeyCode gap, not a
        // crate oversight. Surfaced here rather than silently capping the
        // supported range; see slice 3 spec's Implementation Notes.
        #[cfg(not(target_os = "macos"))]
        "f21" => Ok(Key::F21),
        #[cfg(not(target_os = "macos"))]
        "f22" => Ok(Key::F22),
        #[cfg(not(target_os = "macos"))]
        "f23" => Ok(Key::F23),
        #[cfg(not(target_os = "macos"))]
        "f24" => Ok(Key::F24),
        #[cfg(target_os = "macos")]
        "f21" | "f22" | "f23" | "f24" => {
            Err(format!("{name} is not supported by enigo on macOS"))
        }
        _ => name
            .chars()
            .next()
            .filter(|_| name.chars().count() == 1)
            .map(Key::Unicode)
            .ok_or_else(|| format!("unknown key: {name}")),
    }
}

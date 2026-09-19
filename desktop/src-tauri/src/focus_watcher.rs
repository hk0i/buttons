#![cfg(target_os = "macos")]

use crate::config::{self, Platform};
use crate::server::{apply_profile_switch, ProfileSwitchTx};
use objc2::rc::Retained;
use objc2_app_kit::{
    NSApplicationActivationPolicy, NSRunningApplication, NSWorkspace, NSWorkspaceApplicationKey,
    NSWorkspaceDidActivateApplicationNotification,
};
use objc2_foundation::NSNotification;
use std::path::{Path, PathBuf};
use std::ptr::NonNull;
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::sleep;

// Settle delay before a raw focus-change event is acted on (EDD § 5.5.3)
// — long enough that rapid alt-tabbing fires one switch, not one per raw
// event; short enough the auto-switch still feels immediate.
const DEBOUNCE: Duration = Duration::from_millis(300);

pub fn spawn(
    config_path: PathBuf,
    dirty_tx: crate::ConfigDirtyTx,
    profile_switch_tx: ProfileSwitchTx,
    app: tauri::AppHandle,
) {
    let (raw_tx, mut raw_rx) = mpsc::unbounded_channel::<String>();

    // Registered once, on the main thread (Tauri's `.setup()` hook calls
    // this), for the life of the process — never unregistered. Both the
    // observer token and the block must outlive this function or the
    // observer stops firing; the token isn't Send/Sync (objc2 issue
    // #817), so it can't go through `app.manage()`. `mem::forget` is a
    // deliberate one-time leak, not an oversight — there is exactly one
    // watcher, registered exactly once, for as long as the app runs.
    unsafe {
        let workspace = NSWorkspace::sharedWorkspace();
        let center = workspace.notificationCenter();
        let block = block2::RcBlock::new(move |notification: NonNull<NSNotification>| {
            // Runs on the main thread that posted the notification — must
            // stay cheap. All real work (debounce, config load, the
            // switch itself) happens in the tokio task below.
            if let Some(bundle_id) = bundle_id_from_notification(notification) {
                let _ = raw_tx.send(bundle_id);
            }
        });
        let token = center.addObserverForName_object_queue_usingBlock(
            Some(NSWorkspaceDidActivateApplicationNotification),
            None,
            None,
            &block,
        );
        std::mem::forget(block);
        std::mem::forget(token);
    }

    tauri::async_runtime::spawn(async move {
        // Outer loop: wait for a fresh focus change. Inner loop: keep
        // resetting the settle window on each newer event until it wins
        // (sleep fires uninterrupted) — the sender is leaked above, so
        // `None` (channel closed) is unreachable in practice, not a real
        // exit condition.
        while let Some(mut pending) = raw_rx.recv().await {
            loop {
                tokio::select! {
                    next = raw_rx.recv() => match next {
                        Some(newer) => pending = newer,
                        None => return,
                    },
                    _ = sleep(DEBOUNCE) => break,
                }
            }
            if let Some(id) = matching_profile_id(&config_path, &pending) {
                let _ = apply_profile_switch(id, &config_path, &dirty_tx, &profile_switch_tx, &app).await;
            }
        }
    });
}

// SAFETY: called synchronously from the block above, on the main thread
// that posted the notification, with a valid pointer for the callback's
// duration.
unsafe fn bundle_id_from_notification(notification: NonNull<NSNotification>) -> Option<String> {
    let notification = notification.as_ref();
    let user_info = notification.userInfo()?;
    let running_app = user_info.objectForKey(&*NSWorkspaceApplicationKey)?;
    let running_app: Retained<NSRunningApplication> = running_app.downcast().ok()?;
    running_app.bundleIdentifier().map(|s| s.to_string())
}

// Regular activation policy = Dock/Cmd+Tab-visible — filters out
// background agents and daemons, which have nothing a user would
// recognize to pick from and often no bundle id to associate at all.
pub fn running_apps() -> Vec<(String, String)> {
    let workspace = NSWorkspace::sharedWorkspace();
    workspace
        .runningApplications()
        .iter()
        .filter(|app| app.activationPolicy() == NSApplicationActivationPolicy::Regular)
        .filter_map(|app| {
            let bundle_id = app.bundleIdentifier()?.to_string();
            let name = app
                .localizedName()
                .map(|s| s.to_string())
                .unwrap_or_else(|| bundle_id.clone());
            Some((bundle_id, name))
        })
        .collect()
}

// Loads fresh, not a cached snapshot — same "an edit made on desktop must
// be visible immediately" precedent `execute_press` (server.rs) already
// uses.
fn matching_profile_id(config_path: &Path, focused_bundle_id: &str) -> Option<String> {
    let config = config::load_config(config_path).ok()?;
    config
        .profiles
        .iter()
        .find(|p| {
            p.associated_app_by_platform
                .get(&Platform::MacOs)
                .is_some_and(|id| id == focused_bundle_id)
        })
        .map(|p| p.id.clone())
}

//! Codegen + round-trip prototype only — see
//! `docs/slices/06. Protobuf Codegen Prototype.spec.md`. Not depended on by
//! `/desktop` or `/ios`.

include!(concat!(env!("OUT_DIR"), "/buttons.rs"));

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;

    fn sample_config() -> Config {
        Config {
            profiles: vec![Profile {
                id: "p1".into(),
                name: "Streaming".into(),
                pages: vec![Page {
                    id: "pg1".into(),
                    name: Some("Main".into()),
                    buttons: vec![
                        Button {
                            id: "b1".into(),
                            label: Some("Record".into()),
                            icon: Some("🔴".into()),
                            content: Some(button::Content::Actions(ActionList {
                                actions: vec![
                                    Action {
                                        action: Some(action::Action::Hotkey(Hotkey {
                                            keys: vec!["cmd".into(), "shift".into(), "r".into()],
                                        })),
                                    },
                                    Action {
                                        action: Some(action::Action::MediaKey(
                                            MediaKeyKind::Mute as i32,
                                        )),
                                    },
                                ],
                            })),
                        },
                        Button {
                            id: "b2".into(),
                            label: Some("Tools".into()),
                            icon: None,
                            content: Some(button::Content::Folder(FolderContent {
                                buttons: vec![
                                    Button {
                                        id: "b2-back".into(),
                                        label: None,
                                        icon: None,
                                        content: Some(button::Content::Back(Back {})),
                                    },
                                    Button {
                                        id: "b2-1".into(),
                                        label: Some("Launch OBS".into()),
                                        icon: None,
                                        content: Some(button::Content::Actions(ActionList {
                                            actions: vec![Action {
                                                action: Some(action::Action::LaunchApp(
                                                    LaunchApp {
                                                        path: "/Applications/OBS.app".into(),
                                                    },
                                                )),
                                            }],
                                        })),
                                    },
                                ],
                            })),
                        },
                    ],
                }],
            }],
            active_profile_id: "p1".into(),
        }
    }

    #[test]
    fn round_trip_preserves_full_config() {
        let original = sample_config();
        let bytes = original.encode_to_vec();
        let decoded = Config::decode(bytes.as_slice()).expect("decode");
        assert_eq!(original, decoded);
    }

    /// Presence case 1: nil-vs-empty-string must stay distinguishable
    /// through the round trip (spec finding 3) — a toolchain that
    /// collapses "absent" into "" would still pass a bare equality check
    /// on a Config that never exercises the absent case.
    #[test]
    fn round_trip_distinguishes_absent_label_from_empty_label() {
        let absent = Button {
            id: "absent".into(),
            label: None,
            icon: None,
            content: Some(button::Content::Back(Back {})),
        };
        let empty = Button {
            id: "empty".into(),
            label: Some(String::new()),
            icon: None,
            content: Some(button::Content::Back(Back {})),
        };

        let absent_decoded = Button::decode(absent.encode_to_vec().as_slice()).unwrap();
        let empty_decoded = Button::decode(empty.encode_to_vec().as_slice()).unwrap();

        assert_eq!(absent_decoded.label, None);
        assert_eq!(empty_decoded.label, Some(String::new()));
        assert_ne!(absent_decoded.label, empty_decoded.label);
    }

    /// Presence case 2: a Button whose `content` oneof is set to the empty
    /// `Back{}` message must stay distinguishable from one where no case is
    /// set at all (spec finding 1 / Implementation Note 4) — `.back` means
    /// "no action payload," not "no case selected."
    #[test]
    fn round_trip_distinguishes_back_case_from_unset_oneof() {
        let back_set = Button {
            id: "back".into(),
            label: None,
            icon: None,
            content: Some(button::Content::Back(Back {})),
        };
        let unset = Button {
            id: "unset".into(),
            label: None,
            icon: None,
            content: None,
        };

        let back_decoded = Button::decode(back_set.encode_to_vec().as_slice()).unwrap();
        let unset_decoded = Button::decode(unset.encode_to_vec().as_slice()).unwrap();

        assert!(matches!(back_decoded.content, Some(button::Content::Back(_))));
        assert_eq!(unset_decoded.content, None);
    }
}

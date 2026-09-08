use eframe::egui;

use crate::mock_buttons::{MockButton, MOCK_BUTTONS};

const MIN_CELL_SIZE: f32 = 108.0;
const GAP: f32 = 12.0;

/// Hand-rolled responsive wrap: egui::Grid has no CSS `auto-fill` equivalent,
/// so column count is computed from available width and rows are ended
/// manually. This is the exact unknown the spike exists to surface.
pub fn show(ui: &mut egui::Ui) {
    let available_width = ui.available_width();
    let columns = ((available_width + GAP) / (MIN_CELL_SIZE + GAP))
        .floor()
        .max(1.0) as usize;
    let cell_size = (available_width - GAP * (columns as f32 - 1.0)) / columns as f32;

    egui::Grid::new("button_grid")
        .spacing([GAP, GAP])
        .show(ui, |ui| {
            for (i, button) in MOCK_BUTTONS.iter().enumerate() {
                draw_tile(ui, button, cell_size);
                if (i + 1) % columns == 0 {
                    ui.end_row();
                }
            }
        });
}

fn draw_tile(ui: &mut egui::Ui, button: &MockButton, size: f32) -> egui::Response {
    let (rect, response) =
        ui.allocate_exact_size(egui::vec2(size, size), egui::Sense::click());

    let bg = if response.hovered() {
        egui::Color32::from_rgb(240, 245, 255)
    } else {
        egui::Color32::WHITE
    };

    let rounding = 12.0;
    ui.painter().rect_filled(rect, rounding, bg);
    ui.painter().rect_stroke(
        rect,
        rounding,
        egui::Stroke::new(1.0_f32, egui::Color32::from_gray(220)),
    );

    let icon_pos = rect.center() - egui::vec2(0.0, 12.0);
    ui.painter().text(
        icon_pos,
        egui::Align2::CENTER_CENTER,
        button.icon,
        egui::FontId::proportional(28.0),
        egui::Color32::BLACK,
    );

    let label_pos = rect.center() + egui::vec2(0.0, 20.0);
    ui.painter().text(
        label_pos,
        egui::Align2::CENTER_CENTER,
        button.label,
        egui::FontId::proportional(12.0),
        egui::Color32::from_gray(80),
    );

    response
}

use eframe::egui;

use crate::mock_buttons::{MockButton, MOCK_BUTTONS};

const MIN_CELL_SIZE: f32 = 108.0;
const GAP: f32 = 12.0;

/// Hand-rolled responsive wrap: egui::Grid has no CSS `auto-fill` equivalent,
/// so column count is computed from available width and rows are ended
/// manually. This is the exact unknown the spike exists to surface.
pub fn show(ui: &mut egui::Ui, order: &mut Vec<usize>, dragging: &mut Option<usize>) {
    let available_width = ui.available_width();
    let columns = ((available_width + GAP) / (MIN_CELL_SIZE + GAP))
        .floor()
        .max(1.0) as usize;
    let cell_size = (available_width - GAP * (columns as f32 - 1.0)) / columns as f32;

    let mut swap: Option<(usize, usize)> = None; // (from_pos, to_pos) within `order`

    egui::Grid::new("button_grid")
        .spacing([GAP, GAP])
        .show(ui, |ui| {
            for (pos, &button_idx) in order.iter().enumerate() {
                let button = &MOCK_BUTTONS[button_idx];
                let is_dragging = *dragging == Some(pos);
                let response = draw_tile(ui, button, cell_size, is_dragging);

                if response.drag_started() {
                    *dragging = Some(pos);
                }
                if response.drag_stopped() {
                    *dragging = None;
                }

                if let Some(dragged_pos) = *dragging {
                    if dragged_pos != pos {
                        if let Some(pointer) = ui.ctx().pointer_interact_pos() {
                            if response.rect.contains(pointer) {
                                swap = Some((dragged_pos, pos));
                            }
                        }
                    }
                }

                if (pos + 1) % columns == 0 {
                    ui.end_row();
                }
            }
        });

    if let Some((from, to)) = swap {
        order.swap(from, to);
        *dragging = Some(to);
    }

    // Floating drag ghost: the dragged tile detaches and follows the pointer,
    // instead of only swapping in place — signals "a move is happening" much
    // more clearly than the in-grid dim alone.
    if let Some(dragged_pos) = *dragging {
        if let Some(pointer) = ui.ctx().pointer_interact_pos() {
            let button = &MOCK_BUTTONS[order[dragged_pos]];
            egui::Area::new(egui::Id::new("drag_ghost"))
                .order(egui::Order::Tooltip)
                .fixed_pos(pointer - egui::vec2(cell_size / 2.0, cell_size / 2.0))
                .interactable(false)
                .show(ui.ctx(), |ui| {
                    let (rect, _) =
                        ui.allocate_exact_size(egui::vec2(cell_size, cell_size), egui::Sense::hover());
                    paint_tile(ui, rect, button, 230);
                });
        }
    }
}

fn draw_tile(ui: &mut egui::Ui, button: &MockButton, size: f32, is_dragging: bool) -> egui::Response {
    let (rect, response) =
        ui.allocate_exact_size(egui::vec2(size, size), egui::Sense::click_and_drag());

    let alpha = if is_dragging { 60 } else { 255 };
    paint_tile(ui, rect, button, alpha);

    response
}

fn paint_tile(ui: &mut egui::Ui, rect: egui::Rect, button: &MockButton, alpha: u8) {
    let bg = egui::Color32::from_rgba_unmultiplied(255, 255, 255, alpha);

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
}

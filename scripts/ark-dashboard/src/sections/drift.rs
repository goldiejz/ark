#![allow(dead_code)]

use crate::app::App;
use crate::sections::Section;
use ratatui::{
    layout::{Constraint, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Cell, Row, Table},
    Frame,
};
use std::time::{SystemTime, UNIX_EPOCH};

const TOLERANCE_SECS: u64 = 60;

pub struct DriftDetector;

impl Section for DriftDetector {
    fn name(&self) -> &'static str {
        "Drift"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        let header = Row::new(vec!["Project", "STATE phase", "Newest dir", "Status"])
            .style(Style::default().add_modifier(Modifier::BOLD));

        let now = now_secs();
        let mut drifted = 0usize;
        let total = app.projects.len();

        let rows: Vec<Row> = app
            .projects
            .iter()
            .map(|p| {
                let newest = crate::db::newest_phase_dir(&p.path);
                let newest_basename = newest
                    .as_ref()
                    .map(|(n, _)| n.clone())
                    .unwrap_or_else(|| "(no phases/)".into());

                // Extract leading number prefix from dir basename, e.g. "06-foo" -> "06"
                let dir_num: String = newest_basename
                    .chars()
                    .take_while(|c| c.is_ascii_digit() || *c == '.')
                    .collect();

                let phase_text = &p.current_phase;
                let age = now.saturating_sub(p.last_activity_secs);

                let (color, status) = if !dir_num.is_empty() && phase_text.contains(&dir_num) {
                    (Color::Green, "MATCH".to_string())
                } else if age < TOLERANCE_SECS {
                    (Color::Blue, "INFO (active)".to_string())
                } else {
                    drifted += 1;
                    (Color::Red, "DRIFT".to_string())
                };

                Row::new(vec![
                    Cell::from(truncate(&p.name, 28)),
                    Cell::from(truncate(phase_text, 28)),
                    Cell::from(truncate(&newest_basename, 28)),
                    Cell::from(status).style(Style::default().fg(color)),
                ])
            })
            .collect();

        let widths = [
            Constraint::Length(28),
            Constraint::Length(28),
            Constraint::Length(28),
            Constraint::Min(15),
        ];

        let title_color = if drifted > 0 { Color::Red } else { Color::Green };
        let title = format!(" Drift — {}/{} drifted ", drifted, total);
        let table = Table::new(rows, widths).header(header).block(
            Block::default()
                .title(title)
                .borders(Borders::ALL)
                .border_style(Style::default().fg(title_color))
                .title_style(Style::default().fg(title_color).add_modifier(Modifier::BOLD)),
        );
        f.render_widget(table, area);
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

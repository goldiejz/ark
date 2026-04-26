#![allow(dead_code)]

use crate::app::App;
use crate::sections::Section;
use ratatui::{
    layout::{Constraint, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Cell, Row, Table},
    Frame,
};

pub struct RecentDecisions;

impl Section for RecentDecisions {
    fn name(&self) -> &'static str {
        "Recent Decisions"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        let header = Row::new(vec!["Timestamp", "Class", "Decision", "Reason"])
            .style(Style::default().add_modifier(Modifier::BOLD));

        // Visible window: number of body rows = area.height - 3 (borders + header)
        let visible = (area.height as usize).saturating_sub(3).max(1);
        let total = app.recent_decisions.len();
        let max_offset = total.saturating_sub(visible);
        let offset = app.recent_scroll.min(max_offset);

        let rows: Vec<Row> = app
            .recent_decisions
            .iter()
            .skip(offset)
            .take(visible)
            .map(|d| {
                let color = class_color(&d.class);
                Row::new(vec![
                    Cell::from(truncate(&d.ts, 19)),
                    Cell::from(truncate(&d.class, 18))
                        .style(Style::default().fg(color)),
                    Cell::from(truncate(&d.decision, 22)),
                    Cell::from(truncate(&d.reason, 60)),
                ])
            })
            .collect();

        let widths = [
            Constraint::Length(20),
            Constraint::Length(18),
            Constraint::Length(24),
            Constraint::Min(20),
        ];

        // Per-class breakdown for the title.
        let mut breakdown: std::collections::BTreeMap<&str, usize> = std::collections::BTreeMap::new();
        for d in app.recent_decisions.iter() {
            *breakdown.entry(d.class.as_str()).or_insert(0) += 1;
        }
        let breakdown_str: String = breakdown
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join(" ");

        let title = format!(
            " Recent Decisions — {} rows · scroll {}/{} · [{}] ",
            total,
            offset,
            max_offset,
            if breakdown_str.is_empty() { "—".into() } else { breakdown_str },
        );

        let table = Table::new(rows, widths)
            .header(header)
            .block(Block::default().title(title).borders(Borders::ALL));

        f.render_widget(table, area);
    }
}

fn class_color(class: &str) -> Color {
    match class {
        "escalation" => Color::Red,
        "self_improve" | "lesson_promote" => Color::Cyan,
        "dispatch_failure" => Color::Yellow,
        "budget" => Color::Magenta,
        _ => Color::White,
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

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

pub struct PortfolioGrid;

impl Section for PortfolioGrid {
    fn name(&self) -> &'static str {
        "Portfolio"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        let header = Row::new(vec!["Project", "Phase", "Last activity", "Health"])
            .style(Style::default().add_modifier(Modifier::BOLD));

        let rows: Vec<Row> = app
            .projects
            .iter()
            .map(|p| {
                let color = health_color(p.last_activity_secs);
                let status = health_label(p.last_activity_secs);
                Row::new(vec![
                    Cell::from(truncate(&p.name, 30)),
                    Cell::from(truncate(&p.current_phase, 38)),
                    Cell::from(relative_time(p.last_activity_secs)),
                    Cell::from(status).style(Style::default().fg(color)),
                ])
            })
            .collect();

        let widths = [
            Constraint::Length(30),
            Constraint::Length(38),
            Constraint::Length(15),
            Constraint::Min(10),
        ];

        let title = format!(" Portfolio ({} projects) ", app.projects.len());
        let table = Table::new(rows, widths)
            .header(header)
            .block(Block::default().title(title).borders(Borders::ALL));

        f.render_widget(table, area);
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn health_color(activity_secs: u64) -> Color {
    let now = now_secs();
    let age = now.saturating_sub(activity_secs);
    if age < 86_400 {
        Color::Green
    } else if age < 86_400 * 7 {
        Color::Yellow
    } else {
        Color::Red
    }
}

pub fn health_label(activity_secs: u64) -> &'static str {
    let now = now_secs();
    let age = now.saturating_sub(activity_secs);
    if age < 86_400 {
        "active"
    } else if age < 86_400 * 7 {
        "stale"
    } else {
        "cold"
    }
}

pub fn relative_time(activity_secs: u64) -> String {
    if activity_secs == 0 {
        return "(unknown)".into();
    }
    let now = now_secs();
    let diff = now.saturating_sub(activity_secs);
    if diff < 60 {
        format!("{}s ago", diff)
    } else if diff < 3600 {
        format!("{}m ago", diff / 60)
    } else if diff < 86_400 {
        format!("{}h ago", diff / 3600)
    } else {
        format!("{}d ago", diff / 86_400)
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

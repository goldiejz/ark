#![allow(dead_code)]

use crate::app::App;
use crate::sections::Section;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Cell, Paragraph, Row, Table},
    Frame,
};

pub struct LearningWatch;

impl Section for LearningWatch {
    fn name(&self) -> &'static str {
        "Learning Watch"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        let block = Block::default()
            .title(" Learning Watch ")
            .borders(Borders::ALL);
        let inner = block.inner(area);
        f.render_widget(block, area);

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(3), Constraint::Length(3)])
            .split(inner);

        // ----- Top: Recent promotions -----
        // Filter App's already-loaded recent_decisions for the promotion classes.
        // For a wider time window, we don't requery here — the 06.5-04 refresh
        // pulls 50 rows ordered DESC, which is "recent enough" for the panel.
        let promotions: Vec<_> = app
            .recent_decisions
            .iter()
            .filter(|d| d.class == "self_improve" || d.class == "lesson_promote")
            .take(10)
            .collect();

        if promotions.is_empty() {
            let p = Paragraph::new(Line::from("(no recent promotions in last 50 decisions)"))
                .style(Style::default().fg(Color::DarkGray));
            f.render_widget(p, chunks[0]);
        } else {
            let header = Row::new(vec!["Timestamp", "Decision", "Reason"])
                .style(Style::default().add_modifier(Modifier::BOLD));
            let rows: Vec<Row> = promotions
                .iter()
                .map(|d| {
                    Row::new(vec![
                        Cell::from(truncate(&d.ts, 19)),
                        Cell::from(truncate(&d.decision, 25))
                            .style(Style::default().fg(Color::Cyan)),
                        Cell::from(truncate(&d.reason, 60)),
                    ])
                })
                .collect();
            let widths = [
                Constraint::Length(20),
                Constraint::Length(27),
                Constraint::Min(20),
            ];
            let table = Table::new(rows, widths).header(header);
            f.render_widget(table, chunks[0]);
        }

        // ----- Bottom: Pattern counts -----
        let universal = count_h2_in_file("lessons/universal-patterns.md");
        let anti = count_h2_in_file("bootstrap/anti-patterns.md");

        let footer_line = format!(
            "Universal patterns: {} · Anti-patterns: {} · Conflicts queue: 0",
            universal, anti,
        );
        let footer = Paragraph::new(Line::from(footer_line))
            .style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));
        f.render_widget(footer, chunks[1]);
    }
}

fn count_h2_in_file(rel_to_vault: &str) -> usize {
    let base = std::env::var("ARK_HOME")
        .unwrap_or_else(|_| format!("{}/vaults/ark", std::env::var("HOME").unwrap_or_default()));
    let path = std::path::PathBuf::from(base).join(rel_to_vault);
    let txt = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    txt.lines().filter(|l| l.starts_with("## ")).count()
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

#![allow(dead_code)]

use crate::app::App;
use crate::sections::Section;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub struct EscalationsPanel;

impl Section for EscalationsPanel {
    fn name(&self) -> &'static str {
        "Escalations"
    }

    fn render(&self, f: &mut Frame, area: Rect, _app: &App) {
        let parsed = parse_escalations_file();

        let title_color = if parsed.pending > 0 {
            Color::Red
        } else {
            Color::Green
        };
        let title = format!(
            " Escalations — {} pending · {} resolved ",
            parsed.pending, parsed.resolved
        );

        let block = Block::default()
            .title(title)
            .borders(Borders::ALL)
            .border_style(Style::default().fg(title_color))
            .title_style(
                Style::default()
                    .fg(title_color)
                    .add_modifier(Modifier::BOLD),
            );
        let inner = block.inner(area);
        f.render_widget(block, area);

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(1), Constraint::Length(2)])
            .split(inner);

        if parsed.pending == 0 {
            let p = Paragraph::new(Line::from("No pending blockers."))
                .style(Style::default().fg(Color::Green));
            f.render_widget(p, chunks[0]);
        } else {
            let items: Vec<ListItem> = parsed
                .recent_pending
                .iter()
                .take(10)
                .map(|s| ListItem::new(s.clone()))
                .collect();
            let list = List::new(items).style(Style::default().fg(Color::Red));
            f.render_widget(list, chunks[0]);
        }

        let mut footer_parts: Vec<String> = Vec::new();
        for cls in [
            "budget",
            "architectural",
            "destructive",
            "repeated_failure",
        ] {
            let n = parsed.class_counts.get(cls).copied().unwrap_or(0);
            footer_parts.push(format!("{}={}", cls, n));
        }
        let footer = Paragraph::new(Line::from(footer_parts.join("  ")))
            .style(Style::default().fg(Color::DarkGray));
        f.render_widget(footer, chunks[1]);
    }
}

struct EscParsed {
    pending: usize,
    resolved: usize,
    recent_pending: Vec<String>,
    class_counts: std::collections::HashMap<String, usize>,
}

fn escalations_path() -> std::path::PathBuf {
    if let Ok(p) = std::env::var("ARK_ESCALATIONS_FILE") {
        return std::path::PathBuf::from(p);
    }
    let base = std::env::var("ARK_HOME")
        .unwrap_or_else(|_| format!("{}/vaults/ark", std::env::var("HOME").unwrap_or_default()));
    std::path::PathBuf::from(base).join("ESCALATIONS.md")
}

fn parse_escalations_file() -> EscParsed {
    let mut out = EscParsed {
        pending: 0,
        resolved: 0,
        recent_pending: Vec::new(),
        class_counts: std::collections::HashMap::new(),
    };
    let path = escalations_path();
    let txt = match std::fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => return out,
    };

    let mut in_pending_block = false;
    let mut current_block_class_seen: std::collections::HashSet<String> =
        std::collections::HashSet::new();
    let known = ["budget", "architectural", "destructive", "repeated_failure"];

    for line in txt.lines() {
        if line.starts_with("## [PENDING]") {
            out.pending += 1;
            out.recent_pending.push(line.to_string());
            in_pending_block = true;
            current_block_class_seen.clear();
            continue;
        }
        if line.starts_with("## [RESOLVED]") {
            out.resolved += 1;
            in_pending_block = false;
            current_block_class_seen.clear();
            continue;
        }
        if line.starts_with("## ") {
            in_pending_block = false;
            current_block_class_seen.clear();
            continue;
        }
        if in_pending_block {
            let lower = line.to_ascii_lowercase();
            for k in known.iter() {
                if lower.contains(k) && !current_block_class_seen.contains(*k) {
                    *out.class_counts.entry((*k).to_string()).or_insert(0) += 1;
                    current_block_class_seen.insert((*k).to_string());
                }
            }
        }
    }
    out
}

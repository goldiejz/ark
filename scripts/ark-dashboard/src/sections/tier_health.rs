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
use std::collections::BTreeMap;

pub struct TierHealth;

impl Section for TierHealth {
    fn name(&self) -> &'static str {
        "Tier Health"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        let block = Block::default()
            .title(" Tier Health ")
            .borders(Borders::ALL);
        let inner = block.inner(area);
        f.render_widget(block, area);

        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(2), Constraint::Length(1)])
            .split(inner);

        let report = crate::db::latest_verify_report(&app.vault_path);

        let report_path = match &report {
            Some(p) => p.clone(),
            None => {
                let msg = Paragraph::new(Line::from(
                    "(no verification reports — run `ark verify`)",
                ))
                .style(Style::default().fg(Color::Yellow));
                f.render_widget(msg, chunks[0]);
                return;
            }
        };

        let txt = std::fs::read_to_string(&report_path).unwrap_or_default();
        let counts = parse_tier_counts(&txt);

        let header = Row::new(vec!["Tier", "Pass", "Fail", "Skip", "Status"])
            .style(Style::default().add_modifier(Modifier::BOLD));

        let rows: Vec<Row> = counts
            .iter()
            .map(|(t, (p, fl, s))| {
                let (color, mark) = if *fl > 0 {
                    (Color::Red, "FAIL")
                } else if *p > 0 {
                    (Color::Green, "PASS")
                } else {
                    (Color::DarkGray, "SKIP")
                };
                Row::new(vec![
                    Cell::from(format!("T{}", t)),
                    Cell::from(format!("{}", p)),
                    Cell::from(format!("{}", fl)),
                    Cell::from(format!("{}", s)),
                    Cell::from(mark).style(Style::default().fg(color)),
                ])
            })
            .collect();

        let widths = [
            Constraint::Length(8),
            Constraint::Length(6),
            Constraint::Length(6),
            Constraint::Length(6),
            Constraint::Min(8),
        ];

        if rows.is_empty() {
            let msg = Paragraph::new(Line::from("(report parsed but no tier rows found)"))
                .style(Style::default().fg(Color::Yellow));
            f.render_widget(msg, chunks[0]);
        } else {
            let table = Table::new(rows, widths).header(header);
            f.render_widget(table, chunks[0]);
        }

        let basename = report_path
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        let footer = Paragraph::new(Line::from(format!("Report: {}", basename)))
            .style(Style::default().fg(Color::DarkGray));
        f.render_widget(footer, chunks[1]);
    }
}

/// Parse verify-report text. Looks for lines that contain a `T<num>:` token
/// preceded by a status glyph (✅, ❌, ⏭, ⚠). Returns a sorted-by-tier map.
fn parse_tier_counts(txt: &str) -> BTreeMap<u32, (u32, u32, u32)> {
    let mut out: BTreeMap<u32, (u32, u32, u32)> = BTreeMap::new();
    for line in txt.lines() {
        // Find a `T<digits>:` token.
        let Some(idx) = line.find('T') else { continue };
        let after = &line[idx + 1..];
        // Read digits.
        let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
        if digits.is_empty() {
            continue;
        }
        let after_digits = &after[digits.len()..];
        if !after_digits.starts_with(':') {
            continue;
        }
        let Ok(tier) = digits.parse::<u32>() else { continue };
        let entry = out.entry(tier).or_insert((0, 0, 0));
        if line.contains('✅') {
            entry.0 += 1;
        } else if line.contains('❌') {
            entry.1 += 1;
        } else if line.contains('⏭') {
            entry.2 += 1;
        } else if line.contains('⚠') {
            // count warns as fails for the rollup (non-pass)
            entry.1 += 1;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_tier_counts_basic() {
        let txt = "\
- ✅ T1: a
- ✅ T1: b
- ✅ T7: x
- ❌ T7: y
- ⏭ T12: z
";
        let m = parse_tier_counts(txt);
        assert_eq!(m.get(&1), Some(&(2, 0, 0)));
        assert_eq!(m.get(&7), Some(&(1, 1, 0)));
        assert_eq!(m.get(&12), Some(&(0, 0, 1)));
    }
}

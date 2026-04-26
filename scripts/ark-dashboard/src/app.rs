#![allow(dead_code)]

use crate::db::{Db, Decision, Project};
use crossterm::event::KeyCode;
use std::path::PathBuf;
use std::time::Instant;

pub const NUM_SECTIONS: usize = 7;

pub struct App {
    pub db: Db,
    pub portfolio_root: PathBuf,
    pub vault_path: PathBuf,
    pub projects: Vec<Project>,
    pub recent_decisions: Vec<Decision>,
    pub class_counts: Vec<(String, i64)>,
    pub current_section: usize, // 0..NUM_SECTIONS
    pub recent_scroll: usize,
    pub escalations_selected: usize,
    pub show_help: bool,
    pub should_quit: bool,
    pub last_tick: Instant,
}

impl App {
    pub fn new(db: Db, portfolio_root: PathBuf, vault_path: PathBuf) -> Self {
        let mut app = Self {
            db,
            portfolio_root,
            vault_path,
            projects: Vec::new(),
            recent_decisions: Vec::new(),
            class_counts: Vec::new(),
            current_section: 0,
            recent_scroll: 0,
            escalations_selected: 0,
            show_help: false,
            should_quit: false,
            last_tick: Instant::now(),
        };
        app.refresh();
        app
    }

    /// Refresh all data from disk + db. Errors are swallowed silently
    /// (graceful degradation → empty Vec).
    pub fn refresh(&mut self) {
        self.projects = crate::db::discover_projects(&self.portfolio_root);
        self.recent_decisions = self.db.recent_decisions(50).unwrap_or_default();
        self.class_counts = self.db.counts_by_class().unwrap_or_default();
        self.last_tick = Instant::now();
    }

    /// Parse `~/vaults/ark/ESCALATIONS.md` for the Nth `## [PENDING]` block ID.
    /// Returns None if file missing or selection out of range.
    pub fn escalations_selected_id(&self) -> Option<String> {
        let path = if let Ok(p) = std::env::var("ARK_ESCALATIONS_FILE") {
            PathBuf::from(p)
        } else {
            self.vault_path.join("ESCALATIONS.md")
        };
        let txt = std::fs::read_to_string(&path).ok()?;
        let mut idx = 0usize;
        for line in txt.lines() {
            if line.starts_with("## [PENDING]") {
                if idx == self.escalations_selected {
                    // Try to extract a token that looks like an ID — first
                    // word after "[PENDING]". Conservative: return whole title.
                    let after = line.trim_start_matches("## [PENDING]").trim();
                    if !after.is_empty() {
                        // First whitespace-delimited token.
                        let id = after
                            .split_whitespace()
                            .next()
                            .unwrap_or(after)
                            .to_string();
                        return Some(id);
                    }
                    return None;
                }
                idx += 1;
            }
        }
        None
    }

    pub fn handle_key(&mut self, key: KeyCode) {
        match key {
            KeyCode::Char('q') | KeyCode::Esc => self.should_quit = true,
            KeyCode::Char('?') => self.show_help = !self.show_help,
            KeyCode::Char('r') => {
                // 'r' has TWO behaviors:
                //   - On section 1 (escalations) with a selection: delegate to
                //     `ark escalations --resolve <id>` (single-writer path).
                //   - On any other section: force a refresh (re-tick).
                if self.current_section == 1 {
                    if let Some(id) = self.escalations_selected_id() {
                        let _ = std::process::Command::new("ark")
                            .args(["escalations", "--resolve", &id])
                            .status();
                    }
                }
                self.refresh();
            }
            KeyCode::Enter => {
                // Drill-down placeholder; reserved for Phase 8.
            }
            KeyCode::Char('1') => self.current_section = 0,
            KeyCode::Char('2') => self.current_section = 1,
            KeyCode::Char('3') => self.current_section = 2,
            KeyCode::Char('4') => self.current_section = 3,
            KeyCode::Char('5') => self.current_section = 4,
            KeyCode::Char('6') => self.current_section = 5,
            KeyCode::Char('7') => self.current_section = 6,
            KeyCode::Char('j') | KeyCode::Down => {
                if self.current_section == 3 {
                    self.recent_scroll = self.recent_scroll.saturating_add(1);
                } else if self.current_section == 1 {
                    self.escalations_selected = self.escalations_selected.saturating_add(1);
                } else {
                    self.current_section = (self.current_section + 1) % NUM_SECTIONS;
                }
            }
            KeyCode::Char('k') | KeyCode::Up => {
                if self.current_section == 3 {
                    self.recent_scroll = self.recent_scroll.saturating_sub(1);
                } else if self.current_section == 1 {
                    self.escalations_selected = self.escalations_selected.saturating_sub(1);
                } else {
                    self.current_section =
                        (self.current_section + NUM_SECTIONS - 1) % NUM_SECTIONS;
                }
            }
            KeyCode::Tab => {
                self.current_section = (self.current_section + 1) % NUM_SECTIONS;
            }
            KeyCode::BackTab => {
                self.current_section = (self.current_section + NUM_SECTIONS - 1) % NUM_SECTIONS;
            }
            _ => {}
        }
    }
}

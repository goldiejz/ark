#![allow(dead_code)]

use crate::db::{Db, Decision, Project};
use crossterm::event::KeyCode;
use std::path::PathBuf;
use std::time::Instant;

pub const NUM_SECTIONS: usize = 7;

pub struct App {
    pub db: Db,
    pub portfolio_root: PathBuf,
    pub projects: Vec<Project>,
    pub recent_decisions: Vec<Decision>,
    pub class_counts: Vec<(String, i64)>,
    pub current_section: usize, // 0..NUM_SECTIONS
    pub should_quit: bool,
    pub last_tick: Instant,
}

impl App {
    pub fn new(db: Db, portfolio_root: PathBuf) -> Self {
        let mut app = Self {
            db,
            portfolio_root,
            projects: Vec::new(),
            recent_decisions: Vec::new(),
            class_counts: Vec::new(),
            current_section: 0,
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

    pub fn handle_key(&mut self, key: KeyCode) {
        match key {
            KeyCode::Char('q') | KeyCode::Esc => self.should_quit = true,
            KeyCode::Char('1') => self.current_section = 0,
            KeyCode::Char('2') => self.current_section = 1,
            KeyCode::Char('3') => self.current_section = 2,
            KeyCode::Char('4') => self.current_section = 3,
            KeyCode::Char('5') => self.current_section = 4,
            KeyCode::Char('6') => self.current_section = 5,
            KeyCode::Char('7') => self.current_section = 6,
            KeyCode::Char('j') | KeyCode::Down | KeyCode::Tab => {
                self.current_section = (self.current_section + 1) % NUM_SECTIONS;
            }
            KeyCode::Char('k') | KeyCode::Up | KeyCode::BackTab => {
                self.current_section = (self.current_section + NUM_SECTIONS - 1) % NUM_SECTIONS;
            }
            _ => {}
        }
    }
}

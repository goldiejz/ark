//! App state container

use crate::{employees::Employee, vault};
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct Project {
    pub name: String,
    pub path: PathBuf,
    pub phase: String,
    pub status: String,
    pub decisions: usize,
    pub tokens_month: u64,
    pub budget_tier: String,
    pub lifecycle: String,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub timestamp: String,
    pub project: String,
    pub kind: String,
    pub detail: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tab {
    Projects,
    Employees,
    Events,
    Metrics,
}

pub struct App {
    pub projects_path: PathBuf,
    pub vault_path: PathBuf,
    pub projects: Vec<Project>,
    pub employees: Vec<Employee>,
    pub events: Vec<Event>,
    pub current_tab: Tab,
    pub selected: usize,
    pub show_help: bool,
    pub total_lessons: usize,
    pub total_tokens: u64,
    pub last_refresh: String,
}

impl App {
    pub fn new(projects_path: PathBuf, vault_path: PathBuf) -> Self {
        Self {
            projects_path,
            vault_path,
            projects: vec![],
            employees: vec![],
            events: vec![],
            current_tab: Tab::Projects,
            selected: 0,
            show_help: false,
            total_lessons: 0,
            total_tokens: 0,
            last_refresh: String::new(),
        }
    }

    pub fn refresh_state(&mut self) {
        self.projects = vault::scan_projects(&self.projects_path);
        self.employees = crate::employees::load_employees(&self.vault_path);
        self.events = vault::recent_events(&self.vault_path, 50);
        self.total_lessons = vault::count_lessons(&self.vault_path);
        self.total_tokens = self.projects.iter().map(|p| p.tokens_month).sum();
        self.last_refresh = chrono::Local::now().format("%H:%M:%S").to_string();
    }

    pub fn next_tab(&mut self) {
        self.current_tab = match self.current_tab {
            Tab::Projects => Tab::Employees,
            Tab::Employees => Tab::Events,
            Tab::Events => Tab::Metrics,
            Tab::Metrics => Tab::Projects,
        };
        self.selected = 0;
    }

    pub fn prev_tab(&mut self) {
        self.current_tab = match self.current_tab {
            Tab::Projects => Tab::Metrics,
            Tab::Employees => Tab::Projects,
            Tab::Events => Tab::Employees,
            Tab::Metrics => Tab::Events,
        };
        self.selected = 0;
    }

    pub fn select_next(&mut self) {
        let max = match self.current_tab {
            Tab::Projects => self.projects.len(),
            Tab::Employees => self.employees.len(),
            Tab::Events => self.events.len(),
            Tab::Metrics => 0,
        };
        if max > 0 && self.selected + 1 < max {
            self.selected += 1;
        }
    }

    pub fn select_prev(&mut self) {
        if self.selected > 0 {
            self.selected -= 1;
        }
    }

    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }
}

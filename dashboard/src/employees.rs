//! Employee registry — pluggable agent roster
//!
//! Each .json file in <vault>/employees/ defines a role (architect, engineer, etc.)
//! Drop a new JSON file → new "employee" available for hire.

use serde::{Deserialize, Serialize};
use std::path::Path;
use walkdir::WalkDir;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Dispatch {
    #[serde(rename = "type")]
    pub kind: String, // "claude-subagent", "cli", "api"
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subagent_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Employee {
    pub id: String,
    pub title: String,
    pub department: String,
    pub skills: Vec<String>,
    pub dispatch: Dispatch,
    pub cost_per_task: String, // "free", "low", "medium", "high"
    #[serde(default = "default_status")]
    pub status: String,
    #[serde(default)]
    pub tasks_completed: u64,
    #[serde(default)]
    pub description: String,
}

fn default_status() -> String {
    "available".to_string()
}

pub fn load_employees(vault_path: &Path) -> Vec<Employee> {
    let registry_dir = vault_path.join("employees");
    let mut employees = Vec::new();

    if !registry_dir.exists() {
        return employees;
    }

    for entry in WalkDir::new(&registry_dir)
        .max_depth(2)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        if let Ok(content) = std::fs::read_to_string(path) {
            if let Ok(emp) = serde_json::from_str::<Employee>(&content) {
                employees.push(emp);
            }
        }
    }

    employees.sort_by(|a, b| a.department.cmp(&b.department).then(a.title.cmp(&b.title)));
    employees
}

pub fn cost_color(cost: &str) -> ratatui::style::Color {
    match cost {
        "free" => ratatui::style::Color::Green,
        "low" => ratatui::style::Color::Cyan,
        "medium" => ratatui::style::Color::Yellow,
        "high" => ratatui::style::Color::Red,
        _ => ratatui::style::Color::Gray,
    }
}

pub fn status_color(status: &str) -> ratatui::style::Color {
    match status {
        "available" => ratatui::style::Color::Green,
        "busy" => ratatui::style::Color::Yellow,
        "blocked" => ratatui::style::Color::Red,
        _ => ratatui::style::Color::Gray,
    }
}

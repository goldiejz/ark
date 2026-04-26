//! Vault state scanner — reads project state from filesystem

use crate::app::{Event, Project};
use serde::Deserialize;
use std::{fs, path::Path};
use walkdir::WalkDir;

pub fn scan_projects(projects_path: &Path) -> Vec<Project> {
    let mut projects = Vec::new();

    if !projects_path.exists() {
        return projects;
    }

    for entry in fs::read_dir(projects_path).into_iter().flatten().flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let pa = path.join(".parent-automation");
        if !pa.exists() {
            continue;
        }

        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("?")
            .to_string();

        // Read STATE.md for phase + status
        let (phase, status) = read_state(&path);
        let decisions = count_decisions(&path);
        let (tokens_month, budget_tier) = read_budget(&path);
        let lifecycle = read_lifecycle(&path);

        projects.push(Project {
            name,
            path: path.clone(),
            phase,
            status,
            decisions,
            tokens_month,
            budget_tier,
            lifecycle,
        });
    }

    projects.sort_by(|a, b| a.name.cmp(&b.name));
    projects
}

fn read_state(project: &Path) -> (String, String) {
    let state_file = project.join(".planning/STATE.md");
    let content = fs::read_to_string(&state_file).unwrap_or_default();
    let phase = content
        .lines()
        .find(|l| l.contains("Phase ") && l.starts_with("**"))
        .and_then(|l| {
            l.split(':').nth(1).map(|s| {
                s.replace("**", "")
                    .replace("*", "")
                    .trim()
                    .to_string()
            })
        })
        .unwrap_or_else(|| "?".to_string());
    let status = content
        .lines()
        .find(|l| l.contains("Status:") && l.starts_with("**"))
        .and_then(|l| {
            l.split(':').nth(1).map(|s| {
                s.replace("**", "")
                    .replace("*", "")
                    .trim()
                    .to_string()
            })
        })
        .unwrap_or_else(|| "?".to_string());
    (phase, status)
}

fn count_decisions(project: &Path) -> usize {
    let log = project.join(".planning/bootstrap-decisions.jsonl");
    fs::read_to_string(&log)
        .map(|c| c.lines().filter(|l| !l.trim().is_empty()).count())
        .unwrap_or(0)
}

#[derive(Deserialize)]
struct BudgetFile {
    monthly_used: Option<u64>,
    current_tier: Option<String>,
}

fn read_budget(project: &Path) -> (u64, String) {
    let budget = project.join(".planning/budget.json");
    if let Ok(content) = fs::read_to_string(&budget) {
        if let Ok(b) = serde_json::from_str::<BudgetFile>(&content) {
            return (
                b.monthly_used.unwrap_or(0),
                b.current_tier.unwrap_or_else(|| "GREEN".into()),
            );
        }
    }
    (0, "GREEN".into())
}

#[derive(Deserialize)]
struct LifecycleFile {
    stage: Option<String>,
}

fn read_lifecycle(project: &Path) -> String {
    let lc = project.join(".planning/lifecycle.json");
    fs::read_to_string(&lc)
        .ok()
        .and_then(|c| serde_json::from_str::<LifecycleFile>(&c).ok())
        .and_then(|l| l.stage)
        .unwrap_or_else(|| "active".into())
}

#[derive(Deserialize)]
struct DecisionEntry {
    timestamp: Option<String>,
    #[serde(rename = "projectName")]
    project_name: Option<String>,
    #[serde(rename = "decisionsApplied")]
    decisions_applied: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct BudgetEvent {
    timestamp: Option<String>,
    project: Option<String>,
    new_tier: Option<String>,
    event: Option<String>,
}

pub fn recent_events(vault_path: &Path, limit: usize) -> Vec<Event> {
    let mut events = Vec::new();

    // Budget tier events from vault/observability/budget-events.jsonl
    let budget_log = vault_path.join("observability/budget-events.jsonl");
    if let Ok(content) = fs::read_to_string(&budget_log) {
        for line in content.lines().rev().take(limit) {
            if let Ok(e) = serde_json::from_str::<BudgetEvent>(line) {
                events.push(Event {
                    timestamp: e.timestamp.unwrap_or_default(),
                    project: e.project.unwrap_or_default(),
                    kind: format!("BUDGET → {}", e.new_tier.unwrap_or_default()),
                    detail: e.event.unwrap_or_default(),
                });
            }
        }
    }

    // Decision logs from each project
    let project_root = std::env::var_os("HOME")
        .map(|h| Path::new(&h).join("code"))
        .unwrap_or_else(|| Path::new("./code").to_path_buf());

    for proj in fs::read_dir(&project_root).into_iter().flatten().flatten() {
        let log = proj.path().join(".planning/bootstrap-decisions.jsonl");
        if let Ok(content) = fs::read_to_string(&log) {
            for line in content.lines().rev().take(5) {
                if let Ok(e) = serde_json::from_str::<DecisionEntry>(line) {
                    events.push(Event {
                        timestamp: e.timestamp.unwrap_or_default(),
                        project: e.project_name.unwrap_or_default(),
                        kind: "DECISION".into(),
                        detail: e
                            .decisions_applied
                            .map(|d| d.join(", "))
                            .unwrap_or_default(),
                    });
                }
            }
        }
    }

    // Sort newest first
    events.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    events.truncate(limit);
    events
}

pub fn count_lessons(vault_path: &Path) -> usize {
    let lessons_dir = vault_path.join("lessons");
    let mut count = 0;
    for entry in WalkDir::new(&lessons_dir).into_iter().filter_map(|e| e.ok()) {
        if entry.path().extension().and_then(|s| s.to_str()) == Some("md") {
            count += 1;
        }
    }
    count
}

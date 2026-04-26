#![allow(dead_code)]

use crate::db::Db;

pub struct App {
    pub db: Db,
    pub current_section: usize, // 0..7
    pub should_quit: bool,
    pub last_tick: std::time::Instant,
}

impl App {
    pub fn new(db: Db) -> Self {
        Self {
            db,
            current_section: 0,
            should_quit: false,
            last_tick: std::time::Instant::now(),
        }
    }

    // 06.5-04 will add: tick(), handle_key(), draw()
}

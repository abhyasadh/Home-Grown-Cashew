package database

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	_ "github.com/mattn/go-sqlite3"
)

var (
	db   *sql.DB
	once sync.Once
)

func Initialize(dataDir string) error {
	var initErr error
	once.Do(func() {
		if err := os.MkdirAll(dataDir, 0755); err != nil {
			initErr = fmt.Errorf("create data dir: %w", err)
			return
		}

		dbPath := filepath.Join(dataDir, "cashew.db")
		var err error
		db, err = sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=5000&_foreign_keys=on")
		if err != nil {
			initErr = fmt.Errorf("open database: %w", err)
			return
		}

		db.SetMaxOpenConns(1)

		if err := runMigrations(); err != nil {
			initErr = fmt.Errorf("run migrations: %w", err)
			return
		}
	})
	return initErr
}

func GetDB() *sql.DB {
	return db
}

func Close() {
	if db != nil {
		db.Close()
	}
}

func runMigrations() error {
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id TEXT PRIMARY KEY,
			username TEXT UNIQUE NOT NULL,
			password_hash TEXT NOT NULL,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS backups (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL,
			name TEXT NOT NULL,
			device_name TEXT DEFAULT '',
			schema_version INTEGER DEFAULT 0,
			file_size INTEGER DEFAULT 0,
			file_path TEXT NOT NULL,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS sync_snapshots (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL,
			device_id TEXT NOT NULL,
			file_path TEXT NOT NULL,
			file_size INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS attachments (
			id TEXT PRIMARY KEY,
			user_id TEXT NOT NULL,
			original_name TEXT NOT NULL,
			mime_type TEXT DEFAULT 'application/octet-stream',
			file_path TEXT NOT NULL,
			file_size INTEGER DEFAULT 0,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (user_id) REFERENCES users(id)
		)`,
	}

	for _, m := range migrations {
		if _, err := db.Exec(m); err != nil {
			return fmt.Errorf("exec migration: %w", err)
		}
	}
	return nil
}

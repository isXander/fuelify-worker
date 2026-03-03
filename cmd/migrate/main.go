package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

const migrationsDir = "db/migrations"

func main() {
	log.SetFlags(0)

	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "create":
		if len(os.Args) < 3 {
			log.Fatal("usage: migrate create <name>")
		}
		cmdCreate(os.Args[2])
	case "up":
		withMigrate(func(m *migrate.Migrate) error { return m.Up() })
	case "down":
		n := 1
		if len(os.Args) >= 3 {
			var err error
			if n, err = strconv.Atoi(os.Args[2]); err != nil {
				log.Fatalf("invalid steps: %v", err)
			}
		}
		withMigrate(func(m *migrate.Migrate) error { return m.Steps(-n) })
	case "version":
		withMigrate(func(m *migrate.Migrate) error {
			v, dirty, err := m.Version()
			if err != nil {
				return err
			}
			fmt.Printf("version=%d dirty=%v\n", v, dirty)
			return nil
		})
	case "force":
		if len(os.Args) < 3 {
			log.Fatal("usage: migrate force <version>")
		}
		v, err := strconv.Atoi(os.Args[2])
		if err != nil {
			log.Fatalf("invalid version: %v", err)
		}
		withMigrate(func(m *migrate.Migrate) error { return m.Force(v) })
	default:
		usage()
		os.Exit(1)
	}
}

func cmdCreate(name string) {
	ts := time.Now().UTC().Format("20060102150405")
	base := filepath.Join(migrationsDir, fmt.Sprintf("%s_%s", ts, name))
	for _, ext := range []string{".up.sql", ".down.sql"} {
		path := base + ext
		f, err := os.Create(path)
		if err != nil {
			log.Fatalf("create %s: %v", path, err)
		}
		f.Close()
		fmt.Println("created:", path)
	}
}

func withMigrate(fn func(*migrate.Migrate) error) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal(err)
	}
	srcURL := "file://" + filepath.Join(cwd, migrationsDir)

	m, err := migrate.New(srcURL, dbURL)
	if err != nil {
		log.Fatalf("migrate: %v", err)
	}
	defer m.Close()

	if err := fn(m); err != nil && err != migrate.ErrNoChange {
		log.Fatal(err)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `Usage: go run ./cmd/migrate <command> [args]

Commands:
  create <name>    create a new timestamped migration
  up               run all pending migrations
  down [n]         roll back n migrations (default 1)
  version          show current migration version
  force <version>  force set the migration version
`)
}

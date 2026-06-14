package internal

import (
	"testing"
)

func TestMigrationsEmbedded(t *testing.T) {
	entries, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		t.Fatalf("failed to read embedded migrations: %v", err)
	}
	if len(entries) == 0 {
		t.Fatal("no migration files embedded")
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		data, err := migrationsFS.ReadFile("migrations/" + entry.Name())
		if err != nil {
			t.Errorf("failed to read %s: %v", entry.Name(), err)
		}
		if len(data) == 0 {
			t.Errorf("migration %s is empty", entry.Name())
		}
	}
}

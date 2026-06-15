package main

import (
	"os"
	"testing"
)

func TestMainHelpers(t *testing.T) {
	t.Run("setLogLevel", func(t *testing.T) {
		setLogLevel("debug")
		setLogLevel("info")
		setLogLevel("warn")
		setLogLevel("error")
		setLogLevel("invalid")
	})
}

func TestMainExports(t *testing.T) {
	t.Run("package builds", func(t *testing.T) {
		// Verify the main package can be built
		_ = os.Args
	})
}

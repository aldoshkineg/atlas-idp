package gateway

import "testing"

func TestMarshalRoundTrip(t *testing.T) {
	gw := &Gateway{}
	gw.AddListener("https-app", "app.atlas", "app-cert")
	gw.AddListener("https-other", "other.atlas", "other-cert")

	path := t.TempDir() + "/gw.yaml"
	if err := SaveGateway(path, gw); err != nil {
		t.Fatal(err)
	}

	loaded, err := LoadGateway(path)
	if err != nil {
		t.Fatal(err)
	}

	if len(loaded.Spec.Listeners) != 2 {
		t.Errorf("expected 2 listeners, got %d", len(loaded.Spec.Listeners))
	}

	for _, name := range []string{"https-app", "https-other"} {
		if !loaded.HasListener(name) {
			t.Errorf("missing listener %s after round-trip", name)
		}
	}
}

func TestGateway_RemoveAll(t *testing.T) {
	gw := &Gateway{}
	gw.AddListener("https-a", "a.atlas", "a-cert")
	gw.AddListener("https-b", "b.atlas", "b-cert")

	gw.RemoveListener("https-a")
	gw.RemoveListener("https-b")

	if len(gw.Spec.Listeners) != 0 {
		t.Errorf("expected 0 listeners after removing all, got %d", len(gw.Spec.Listeners))
	}
}

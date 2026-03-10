package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"tailscale.com/tsnet"
)

func main() {
	hostname := os.Getenv("E2B_SANDBOX_ID")
	if hostname == "" {
		hostname = "e2b-tsnet"
	}
	authKey := os.Getenv("TS_AUTHKEY")
	if authKey == "" {
		log.Fatal("TS_AUTHKEY required")
	}

	srv := &tsnet.Server{
		Hostname: hostname,
		AuthKey:  authKey,
		Dir:      "/tmp/tsnet-state",
		Logf:     log.Printf,
	}

	log.Printf("[tsnet-bridge] starting as %s", hostname)

	status, err := srv.Up(nil)
	if err != nil {
		log.Fatalf("tsnet.Up: %v", err)
	}
	log.Printf("[tsnet-bridge] UP! TailscaleIPs: %v", status.TailscaleIPs)

	ln, err := srv.Listen("tcp", ":8888")
	if err != nil {
		log.Fatalf("Listen: %v", err)
	}
	log.Printf("[tsnet-bridge] listening on %s.tailnet:8888", hostname)

	lc, _ := srv.LocalClient()

	mux := http.NewServeMux()
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		info := map[string]interface{}{
			"hostname":  hostname,
			"sandbox":   os.Getenv("E2B_SANDBOX_ID"),
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"alive":     true,
		}
		if lc != nil {
			if st, e := lc.Status(r.Context()); e == nil {
				info["tailscale_ips"] = st.TailscaleIPs
				info["peer_count"] = len(st.Peer)
				info["magic_dns"] = fmt.Sprintf("%s.tailXXXX.ts.net", hostname)
			}
		}
		json.NewEncoder(w).Encode(info)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "tsnet-bridge @ %s alive\n", hostname)
	})

	log.Fatal(http.Serve(ln, mux))
}

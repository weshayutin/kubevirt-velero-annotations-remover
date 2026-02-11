package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
)

const (
	tlsCert = "/tls/tls.crt"
	tlsKey  = "/tls/tls.key"
)

// AdmissionReview represents a Kubernetes admission review request/response
type AdmissionReview struct {
	APIVersion string             `json:"apiVersion"`
	Kind       string             `json:"kind"`
	Request    *AdmissionRequest  `json:"request,omitempty"`
	Response   *AdmissionResponse `json:"response,omitempty"`
}

// AdmissionRequest contains the admission request data
type AdmissionRequest struct {
	UID       string          `json:"uid"`
	Operation string          `json:"operation"`
	Object    json.RawMessage `json:"object"`
}

// AdmissionResponse contains the admission response data
type AdmissionResponse struct {
	UID       string `json:"uid"`
	Allowed   bool   `json:"allowed"`
	PatchType string `json:"patchType,omitempty"`
	Patch     string `json:"patch,omitempty"`
}

// PodMetadata represents the metadata section of a pod
type PodMetadata struct {
	Name        string            `json:"name"`
	Namespace   string            `json:"namespace"`
	Labels      map[string]string `json:"labels"`
	Annotations map[string]string `json:"annotations"`
}

// Pod represents a Kubernetes pod with metadata
type Pod struct {
	Metadata PodMetadata `json:"metadata"`
}

// JSONPatchOperation represents a JSON patch operation
type JSONPatchOperation struct {
	Op   string `json:"op"`
	Path string `json:"path"`
}

func main() {
	// Setup structured logging
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// Check TLS certificate files exist
	if _, err := os.Stat(tlsCert); os.IsNotExist(err) {
		slog.Error("TLS certificate not found", "path", tlsCert)
	}
	if _, err := os.Stat(tlsKey); os.IsNotExist(err) {
		slog.Error("TLS key not found", "path", tlsKey)
	}

	// Setup HTTP handler
	http.HandleFunc("/mutate", mutateHandler)

	// Start HTTPS server
	slog.Info("Starting webhook server...")
	addr := "0.0.0.0:8443"
	if err := http.ListenAndServeTLS(addr, tlsCert, tlsKey, nil); err != nil {
		slog.Error("Failed to start server", "error", err)
		os.Exit(1)
	}
}

func mutateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse admission review request
	var admissionReview AdmissionReview
	if err := json.NewDecoder(r.Body).Decode(&admissionReview); err != nil {
		slog.Error("Failed to decode request", "error", err)
		writeErrorResponse(w, admissionReview.Request)
		return
	}

	// Process the request
	response := processAdmissionRequest(admissionReview.Request)

	// Send response
	admissionReview.Response = response
	admissionReview.Request = nil // Clear request from response

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(admissionReview); err != nil {
		slog.Error("Failed to encode response", "error", err)
	}
}

func processAdmissionRequest(request *AdmissionRequest) *AdmissionResponse {
	if request == nil {
		return &AdmissionResponse{Allowed: true}
	}

	// Parse pod object
	var pod Pod
	if err := json.Unmarshal(request.Object, &pod); err != nil {
		slog.Error("Failed to parse pod object", "error", err)
		return &AdmissionResponse{
			UID:     request.UID,
			Allowed: true,
		}
	}

	// Extract VM context information
	podName := pod.Metadata.Name
	if podName == "" {
		podName = "unknown"
	}
	namespace := pod.Metadata.Namespace
	if namespace == "" {
		namespace = "unknown"
	}
	vmName := pod.Metadata.Labels["kubevirt.io/domain"]
	if vmName == "" {
		vmName = "unknown"
	}
	operation := request.Operation
	if operation == "" {
		operation = "unknown"
	}

	// Log processing start with VM details
	slog.Info("Processing admission request",
		"operation", operation,
		"vm", vmName,
		"pod", podName,
		"namespace", namespace)

	// Process annotations and build patch
	var patches []JSONPatchOperation
	for key, value := range pod.Metadata.Annotations {
		if strings.HasPrefix(key, "pre.hook.backup.velero.io/") ||
			strings.HasPrefix(key, "post.hook.backup.velero.io/") {
			// Log each annotation being removed
			slog.Info("  Removing annotation", "key", key, "value", value)

			// Escape the key for JSON path (replace / with ~1)
			escapedKey := strings.ReplaceAll(key, "/", "~1")
			patches = append(patches, JSONPatchOperation{
				Op:   "remove",
				Path: fmt.Sprintf("/metadata/annotations/%s", escapedKey),
			})
		}
	}

	// Log summary
	if len(patches) > 0 {
		slog.Info("Removed Velero backup hook annotations",
			"count", len(patches),
			"vm", vmName)
	} else {
		slog.Info("No Velero annotations found - no changes needed",
			"vm", vmName)
	}

	// Encode patch as base64
	var patchBytes []byte
	var err error
	if len(patches) > 0 {
		patchBytes, err = json.Marshal(patches)
		if err != nil {
			slog.Error("Failed to marshal patch", "error", err)
			return &AdmissionResponse{
				UID:     request.UID,
				Allowed: true,
			}
		}
	} else {
		// Empty patch
		patchBytes = []byte("[]")
	}

	return &AdmissionResponse{
		UID:       request.UID,
		Allowed:   true,
		PatchType: "JSONPatch",
		Patch:     base64.StdEncoding.EncodeToString(patchBytes),
	}
}

func writeErrorResponse(w http.ResponseWriter, request *AdmissionRequest) {
	uid := ""
	if request != nil {
		uid = request.UID
	}

	response := AdmissionReview{
		APIVersion: "admission.k8s.io/v1",
		Kind:       "AdmissionReview",
		Response: &AdmissionResponse{
			UID:     uid,
			Allowed: true,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

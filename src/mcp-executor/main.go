// mcp-executor — Ejecutor MCP estático para netbook Linux
// Hardware objetivo: Intel Atom N2600, 2GB RAM
// Recibe JSON-RPC 2.0 por stdin, ejecuta herramientas, responde por stdout
// Compilar: CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o mcp-executor .

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// =============================================================
// ESTRUCTURAS JSON-RPC 2.0
// =============================================================

type JSONRPCRequest struct {
	JSONRPC string                 `json:"jsonrpc"`
	ID      interface{}            `json:"id"`
	Method  string                 `json:"method"`
	Params  map[string]interface{} `json:"params"`
}

type JSONRPCResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   *RPCError   `json:"error,omitempty"`
}

type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type ToolResult struct {
	Content []ContentBlock `json:"content"`
}

type ContentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// =============================================================
// RESPUESTAS AUXILIARES
// =============================================================

func respond(id interface{}, result interface{}) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	}
	data, _ := json.Marshal(resp)
	fmt.Println(string(data))
}

func respondError(id interface{}, code int, message string) {
	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error: &RPCError{
			Code:    code,
			Message: message,
		},
	}
	data, _ := json.Marshal(resp)
	fmt.Println(string(data))
}

func textResult(id interface{}, text string) {
	respond(id, ToolResult{
		Content: []ContentBlock{{Type: "text", Text: text}},
	})
}

// =============================================================
// HERRAMIENTAS MCP
// =============================================================

// tool_run_shell: Ejecuta un comando shell con timeout
func toolRunShell(id interface{}, args map[string]interface{}) {
	command, ok := args["command"].(string)
	if !ok || command == "" {
		respondError(id, -32602, "Parámetro 'command' requerido")
		return
	}

	timeoutSec := 60
	if t, ok := args["timeout"].(float64); ok {
		timeoutSec = int(t)
	}
	if timeoutSec > 120 {
		timeoutSec = 120
	}

	cmd := exec.Command("bash", "-c", command)
	cmd.Env = append(os.Environ(), "HOME=/tmp")

	// Captura de salida con timeout manual
	done := make(chan struct{})
	var output []byte
	var runErr error

	go func() {
		defer close(done)
		output, runErr = cmd.CombinedOutput()
	}()

	select {
	case <-done:
		// completado
	case <-time.After(time.Duration(timeoutSec) * time.Second):
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		textResult(id, fmt.Sprintf("[TIMEOUT] El comando superó %d segundos.", timeoutSec))
		return
	}

	result := string(output)
	if runErr != nil {
		result = fmt.Sprintf("[EXIT ERROR: %v]\n%s", runErr, result)
	}
	if result == "" {
		result = "[Sin salida]"
	}

	textResult(id, result)
}

// tool_file_read: Lee el contenido de un archivo
func toolFileRead(id interface{}, args map[string]interface{}) {
	path, ok := args["path"].(string)
	if !ok || path == "" {
		respondError(id, -32602, "Parámetro 'path' requerido")
		return
	}

	// Validación de seguridad: solo rutas absolutas dentro de directorios permitidos
	cleanPath := filepath.Clean(path)
	allowed := []string{"/home", "/tmp", "/var/log/mcp-node", "/etc/mcp-node"}
	isAllowed := false
	for _, prefix := range allowed {
		if strings.HasPrefix(cleanPath, prefix) {
			isAllowed = true
			break
		}
	}
	if !isAllowed {
		respondError(id, -32602, fmt.Sprintf("Ruta no permitida: %s", cleanPath))
		return
	}

	data, err := os.ReadFile(cleanPath)
	if err != nil {
		textResult(id, fmt.Sprintf("[ERROR al leer]: %v", err))
		return
	}

	content := string(data)
	// Limitar a 10KB para no sobrecargar
	if len(content) > 10240 {
		content = content[:10240] + "\n[... truncado a 10KB ...]"
	}

	textResult(id, content)
}

// tool_file_write: Escribe contenido en un archivo (solo en /tmp y /home)
func toolFileWrite(id interface{}, args map[string]interface{}) {
	path, ok := args["path"].(string)
	if !ok || path == "" {
		respondError(id, -32602, "Parámetro 'path' requerido")
		return
	}
	content, _ := args["content"].(string)

	cleanPath := filepath.Clean(path)
	if !strings.HasPrefix(cleanPath, "/tmp") && !strings.HasPrefix(cleanPath, "/home") {
		respondError(id, -32602, "Escritura solo permitida en /tmp y /home")
		return
	}

	if err := os.MkdirAll(filepath.Dir(cleanPath), 0755); err != nil {
		textResult(id, fmt.Sprintf("[ERROR al crear directorio]: %v", err))
		return
	}

	if err := os.WriteFile(cleanPath, []byte(content), 0644); err != nil {
		textResult(id, fmt.Sprintf("[ERROR al escribir]: %v", err))
		return
	}

	textResult(id, fmt.Sprintf("Archivo escrito: %s (%d bytes)", cleanPath, len(content)))
}

// tool_status: Devuelve estado del sistema
func toolStatus(id interface{}) {
	cmd := exec.Command("bash", "-c",
		`echo "=== ESTADO DEL SISTEMA ===" && `+
		`echo "Fecha: $(date)" && `+
		`echo "Uptime: $(uptime -p 2>/dev/null || uptime)" && `+
		`echo "Memoria libre: $(free -m | awk '/^Mem/{print $4}') MB" && `+
		`echo "Swap (ZRAM): $(free -m | awk '/^Swap/{print $3}') MB usados" && `+
		`echo "CPU load: $(cat /proc/loadavg | cut -d' ' -f1-3)" && `+
		`echo "Disco /: $(df -h / | awk 'NR==2{print $5}') usado" && `+
		`echo "Temperatura: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf \"%.1f°C\", $1/1000}' || echo N/A)"`)

	output, _ := cmd.CombinedOutput()
	textResult(id, string(output))
}

// =============================================================
// LISTA DE HERRAMIENTAS (tools/list)
// =============================================================

func handleToolsList(id interface{}) {
	tools := map[string]interface{}{
		"tools": []map[string]interface{}{
			{
				"name":        "run_shell",
				"description": "Ejecuta un comando bash en el sistema local",
				"inputSchema": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"command": map[string]string{"type": "string", "description": "Comando bash a ejecutar"},
						"timeout": map[string]string{"type": "number", "description": "Timeout en segundos (máx 120)"},
					},
					"required": []string{"command"},
				},
			},
			{
				"name":        "file_read",
				"description": "Lee el contenido de un archivo del sistema",
				"inputSchema": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"path": map[string]string{"type": "string", "description": "Ruta absoluta del archivo"},
					},
					"required": []string{"path"},
				},
			},
			{
				"name":        "file_write",
				"description": "Escribe contenido en un archivo (solo /tmp y /home)",
				"inputSchema": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"path":    map[string]string{"type": "string"},
						"content": map[string]string{"type": "string"},
					},
					"required": []string{"path", "content"},
				},
			},
			{
				"name":        "system_status",
				"description": "Devuelve estado de memoria, CPU y disco del sistema",
				"inputSchema": map[string]interface{}{
					"type":       "object",
					"properties": map[string]interface{}{},
				},
			},
		},
	}
	respond(id, tools)
}

// =============================================================
// DESPACHADOR PRINCIPAL
// =============================================================

func dispatch(req JSONRPCRequest) {
	switch req.Method {
	case "initialize":
		respond(req.ID, map[string]interface{}{
			"protocolVersion": "2024-11-05",
			"capabilities":    map[string]interface{}{"tools": map[string]bool{"listChanged": false}},
			"serverInfo":      map[string]string{"name": "netbook-mcp-executor", "version": "1.0.0"},
		})

	case "tools/list":
		handleToolsList(req.ID)

	case "tools/call":
		toolName, _ := req.Params["name"].(string)
		arguments, _ := req.Params["arguments"].(map[string]interface{})

		switch toolName {
		case "run_shell":
			toolRunShell(req.ID, arguments)
		case "file_read":
			toolFileRead(req.ID, arguments)
		case "file_write":
			toolFileWrite(req.ID, arguments)
		case "system_status":
			toolStatus(req.ID)
		default:
			respondError(req.ID, -32601, fmt.Sprintf("Herramienta no encontrada: %s", toolName))
		}

	default:
		respondError(req.ID, -32601, fmt.Sprintf("Método no soportado: %s", req.Method))
	}
}

// =============================================================
// MAIN — Lee stdin línea por línea
// =============================================================

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var req JSONRPCRequest
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			respondError(nil, -32700, fmt.Sprintf("JSON inválido: %v", err))
			continue
		}

		dispatch(req)
	}
}

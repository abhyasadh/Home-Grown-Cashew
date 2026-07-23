package web

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

type WebHandler struct {
	WebDir string
}

func NewWebHandler(webDir string) *WebHandler {
	return &WebHandler{WebDir: webDir}
}

func (h *WebHandler) Serve(c *gin.Context) {
	if h.WebDir == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "web build not configured"})
		return
	}

	path := c.Param("path")
	if path == "" {
		path = "index.html"
	}

	filePath := filepath.Join(h.WebDir, path)

	// Prevent directory traversal
	if !strings.HasPrefix(filepath.Clean(filePath), filepath.Clean(h.WebDir)) {
		c.JSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}

	// If file doesn't exist and it's not a static asset, serve index.html (SPA routing)
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		if !isStaticAsset(path) {
			filePath = filepath.Join(h.WebDir, "index.html")
		} else {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
	}

	c.File(filePath)
}

func isStaticAsset(path string) bool {
	extensions := []string{".js", ".css", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".eot", ".map", ".json"}
	lower := strings.ToLower(path)
	for _, ext := range extensions {
		if strings.HasSuffix(lower, ext) {
			return true
		}
	}
	return false
}

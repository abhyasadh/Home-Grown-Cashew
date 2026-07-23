package main

import (
	"cashew-server/internal/attachment"
	"cashew-server/internal/auth"
	"cashew-server/internal/backup"
	"cashew-server/internal/database"
	"cashew-server/internal/sync"
	"cashew-server/internal/web"
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
)

func main() {
	dataDir := getEnv("DATA_DIR", "./data")
	webDir := getEnv("WEB_DIR", "./web/build")
	jwtSecret := getEnv("JWT_SECRET", "")
	port := getEnv("PORT", "2580")

	if err := database.Initialize(dataDir); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	auth.InitSecret(jwtSecret)

	backupStorage := backup.NewBackupStorage(dataDir)
	syncStorage := sync.NewSyncStorage(dataDir)
	attachmentStorage := attachment.NewAttachmentStorage(dataDir)
	webHandler := web.NewWebHandler(webDir)

	r := gin.Default()

	// CORS middleware
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// Health check (public)
	r.GET("/api/health", auth.Health)

	// Auth routes (public for register/login)
	r.POST("/api/auth/register", auth.Register)
	r.POST("/api/auth/login", auth.Login)

	// Protected routes
	api := r.Group("/api")
	api.Use(auth.Middleware())
	{
		api.GET("/auth/me", auth.GetMe)

		// Backup routes
		api.GET("/backups", backupStorage.ListBackups)
		api.POST("/backups", backupStorage.UploadBackup)
		api.GET("/backups/:id", backupStorage.DownloadBackup)
		api.DELETE("/backups/:id", backupStorage.DeleteBackup)

		// Sync routes
		api.POST("/sync/upload", syncStorage.UploadSnapshot)
		api.GET("/sync/download", syncStorage.DownloadLatestSnapshot)
		api.GET("/sync/status", syncStorage.GetStatus)
		api.GET("/sync/snapshots", syncStorage.ListSnapshots)
		api.GET("/sync/snapshots/:deviceId", syncStorage.DownloadDeviceSnapshot)

		// Attachment routes
		api.POST("/attachments", attachmentStorage.Upload)
		api.GET("/attachments", attachmentStorage.List)
		api.GET("/attachments/:id", attachmentStorage.Download)
		api.DELETE("/attachments/:id", attachmentStorage.Delete)
	}

	// Serve Flutter web build (catch-all, must be last)
	r.NoRoute(webHandler.Serve)

	addr := fmt.Sprintf(":%s", port)
	log.Printf("Cashew server starting on %s", addr)
	log.Printf("Data directory: %s", dataDir)
	log.Printf("Web directory: %s", webDir)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

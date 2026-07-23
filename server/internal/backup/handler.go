package backup

import (
	"cashew-server/internal/database"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type BackupStorage struct {
	DataDir string
}

func NewBackupStorage(dataDir string) *BackupStorage {
	return &BackupStorage{DataDir: dataDir}
}

type BackupInfo struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	DeviceName     string `json:"deviceName"`
	SchemaVersion  int    `json:"schemaVersion"`
	FileSize       int64  `json:"fileSize"`
	CreatedAt      string `json:"createdAt"`
}

func (s *BackupStorage) ListBackups(c *gin.Context) {
	userID := c.GetString("userID")

	rows, err := database.GetDB().Query(
		"SELECT id, name, device_name, schema_version, file_size, created_at FROM backups WHERE user_id = ? ORDER BY created_at DESC",
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list backups"})
		return
	}
	defer rows.Close()

	backups := []BackupInfo{}
	for rows.Next() {
		var b BackupInfo
		rows.Scan(&b.ID, &b.Name, &b.DeviceName, &b.SchemaVersion, &b.FileSize, &b.CreatedAt)
		backups = append(backups, b)
	}

	c.JSON(http.StatusOK, gin.H{"backups": backups})
}

func (s *BackupStorage) UploadBackup(c *gin.Context) {
	userID := c.GetString("userID")

	file, _, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing file"})
		return
	}
	defer file.Close()

	name := c.PostForm("name")
	deviceName := c.PostForm("deviceName")
	schemaVersion, _ := strconv.Atoi(c.PostForm("schemaVersion"))

	if name == "" {
		name = fmt.Sprintf("backup-%s", time.Now().Format("2006-01-02-150405"))
	}

	id := uuid.New().String()
	backupDir := filepath.Join(s.DataDir, "backups", userID)
	os.MkdirAll(backupDir, 0755)

	filePath := filepath.Join(backupDir, id+".sqlite")
	dst, err := os.Create(filePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create file"})
		return
	}
	defer dst.Close()

	written, err := io.Copy(dst, file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save file"})
		return
	}

	_, err = database.GetDB().Exec(
		"INSERT INTO backups (id, user_id, name, device_name, schema_version, file_size, file_path) VALUES (?, ?, ?, ?, ?, ?, ?)",
		id, userID, name, deviceName, schemaVersion, written, filePath,
	)
	if err != nil {
		os.Remove(filePath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save backup record"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":        id,
		"name":      name,
		"fileSize":  written,
		"createdAt": time.Now().Format(time.RFC3339),
	})
}

func (s *BackupStorage) DownloadBackup(c *gin.Context) {
	userID := c.GetString("userID")
	backupID := c.Param("id")

	var filePath, name string
	err := database.GetDB().QueryRow(
		"SELECT file_path, name FROM backups WHERE id = ? AND user_id = ?",
		backupID, userID,
	).Scan(&filePath, &name)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "backup not found"})
		return
	}

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "backup file missing"})
		return
	}

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s.sqlite", name))
	c.File(filePath)
}

func (s *BackupStorage) DeleteBackup(c *gin.Context) {
	userID := c.GetString("userID")
	backupID := c.Param("id")

	var filePath string
	err := database.GetDB().QueryRow(
		"SELECT file_path FROM backups WHERE id = ? AND user_id = ?",
		backupID, userID,
	).Scan(&filePath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "backup not found"})
		return
	}

	database.GetDB().Exec("DELETE FROM backups WHERE id = ? AND user_id = ?", backupID, userID)
	os.Remove(filePath)

	c.JSON(http.StatusOK, gin.H{"message": "backup deleted"})
}

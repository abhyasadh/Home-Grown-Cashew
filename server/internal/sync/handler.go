package sync

import (
	"cashew-server/internal/database"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type SyncStorage struct {
	DataDir string
}

func NewSyncStorage(dataDir string) *SyncStorage {
	return &SyncStorage{DataDir: dataDir}
}

type SyncSnapshot struct {
	ID        string `json:"id"`
	DeviceID  string `json:"deviceId"`
	FileSize  int64  `json:"fileSize"`
	CreatedAt string `json:"createdAt"`
}

func (s *SyncStorage) UploadSnapshot(c *gin.Context) {
	userID := c.GetString("userID")

	file, _, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing file"})
		return
	}
	defer file.Close()

	deviceID := c.PostForm("deviceId")
	if deviceID == "" {
		deviceID = "unknown"
	}

	// Delete existing snapshot for this device
	var oldPath string
	err = database.GetDB().QueryRow(
		"SELECT file_path FROM sync_snapshots WHERE user_id = ? AND device_id = ?",
		userID, deviceID,
	).Scan(&oldPath)
	if err == nil {
		database.GetDB().Exec(
			"DELETE FROM sync_snapshots WHERE user_id = ? AND device_id = ?",
			userID, deviceID,
		)
		os.Remove(oldPath)
	}

	id := uuid.New().String()
	syncDir := filepath.Join(s.DataDir, "sync", userID)
	os.MkdirAll(syncDir, 0755)

	filePath := filepath.Join(syncDir, id+".sqlite")
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
		"INSERT INTO sync_snapshots (id, user_id, device_id, file_path, file_size) VALUES (?, ?, ?, ?, ?)",
		id, userID, deviceID, filePath, written,
	)
	if err != nil {
		os.Remove(filePath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save record"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":        id,
		"deviceId":  deviceID,
		"fileSize":  written,
		"createdAt": time.Now().Format(time.RFC3339),
	})
}

func (s *SyncStorage) DownloadLatestSnapshot(c *gin.Context) {
	userID := c.GetString("userID")

	var filePath string
	var fileSize int64
	var createdAt string
	err := database.GetDB().QueryRow(
		"SELECT file_path, file_size, created_at FROM sync_snapshots WHERE user_id = ? ORDER BY created_at DESC LIMIT 1",
		userID,
	).Scan(&filePath, &fileSize, &createdAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no sync snapshots found"})
		return
	}

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "sync file missing"})
		return
	}

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=sync-%s.sqlite", userID))
	c.File(filePath)
}

func (s *SyncStorage) GetStatus(c *gin.Context) {
	userID := c.GetString("userID")

	var latestTime string
	var deviceCount int
	database.GetDB().QueryRow(
		"SELECT COUNT(*) FROM sync_snapshots WHERE user_id = ?", userID,
	).Scan(&deviceCount)
	database.GetDB().QueryRow(
		"SELECT created_at FROM sync_snapshots WHERE user_id = ? ORDER BY created_at DESC LIMIT 1",
		userID,
	).Scan(&latestTime)

	c.JSON(http.StatusOK, gin.H{
		"lastSynced":  latestTime,
		"deviceCount": deviceCount,
	})
}

func (s *SyncStorage) DownloadDeviceSnapshot(c *gin.Context) {
	userID := c.GetString("userID")
	deviceID := c.Param("deviceId")

	var filePath string
	err := database.GetDB().QueryRow(
		"SELECT file_path FROM sync_snapshots WHERE user_id = ? AND device_id = ?",
		userID, deviceID,
	).Scan(&filePath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "snapshot not found for device"})
		return
	}

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "file missing"})
		return
	}

	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=sync-%s.sqlite", deviceID))
	c.File(filePath)
}

func (s *SyncStorage) ListSnapshots(c *gin.Context) {
	userID := c.GetString("userID")

	rows, err := database.GetDB().Query(
		"SELECT id, device_id, file_size, created_at FROM sync_snapshots WHERE user_id = ? ORDER BY created_at DESC",
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list snapshots"})
		return
	}
	defer rows.Close()

	snapshots := []SyncSnapshot{}
	for rows.Next() {
		var snap SyncSnapshot
		rows.Scan(&snap.ID, &snap.DeviceID, &snap.FileSize, &snap.CreatedAt)
		snapshots = append(snapshots, snap)
	}

	c.JSON(http.StatusOK, gin.H{"snapshots": snapshots})
}

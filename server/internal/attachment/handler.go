package attachment

import (
	"cashew-server/internal/database"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type AttachmentStorage struct {
	DataDir string
}

func NewAttachmentStorage(dataDir string) *AttachmentStorage {
	return &AttachmentStorage{DataDir: dataDir}
}

type AttachmentInfo struct {
	ID           string `json:"id"`
	OriginalName string `json:"originalName"`
	MimeType     string `json:"mimeType"`
	FileSize     int64  `json:"fileSize"`
	CreatedAt    string `json:"createdAt"`
}

func (s *AttachmentStorage) Upload(c *gin.Context) {
	userID := c.GetString("userID")

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing file"})
		return
	}
	defer file.Close()

	mimeType := header.Header.Get("Content-Type")
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}

	id := uuid.New().String()
	attachDir := filepath.Join(s.DataDir, "attachments", userID)
	os.MkdirAll(attachDir, 0755)

	filePath := filepath.Join(attachDir, id+filepath.Ext(header.Filename))
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
		"INSERT INTO attachments (id, user_id, original_name, mime_type, file_path, file_size) VALUES (?, ?, ?, ?, ?, ?)",
		id, userID, header.Filename, mimeType, filePath, written,
	)
	if err != nil {
		os.Remove(filePath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save record"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"id":           id,
		"originalName": header.Filename,
		"mimeType":     mimeType,
		"fileSize":     written,
	})
}

func (s *AttachmentStorage) Download(c *gin.Context) {
	userID := c.GetString("userID")
	attachID := c.Param("id")

	var filePath, originalName, mimeType string
	err := database.GetDB().QueryRow(
		"SELECT file_path, original_name, mime_type FROM attachments WHERE id = ? AND user_id = ?",
		attachID, userID,
	).Scan(&filePath, &originalName, &mimeType)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "attachment not found"})
		return
	}

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "file missing"})
		return
	}

	c.Header("Content-Type", mimeType)
	c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", originalName))
	c.File(filePath)
}

func (s *AttachmentStorage) Delete(c *gin.Context) {
	userID := c.GetString("userID")
	attachID := c.Param("id")

	var filePath string
	err := database.GetDB().QueryRow(
		"SELECT file_path FROM attachments WHERE id = ? AND user_id = ?",
		attachID, userID,
	).Scan(&filePath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "attachment not found"})
		return
	}

	database.GetDB().Exec("DELETE FROM attachments WHERE id = ? AND user_id = ?", attachID, userID)
	os.Remove(filePath)

	c.JSON(http.StatusOK, gin.H{"message": "attachment deleted"})
}

func (s *AttachmentStorage) List(c *gin.Context) {
	userID := c.GetString("userID")

	rows, err := database.GetDB().Query(
		"SELECT id, original_name, mime_type, file_size, created_at FROM attachments WHERE user_id = ? ORDER BY created_at DESC",
		userID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list attachments"})
		return
	}
	defer rows.Close()

	attachments := []AttachmentInfo{}
	for rows.Next() {
		var a AttachmentInfo
		rows.Scan(&a.ID, &a.OriginalName, &a.MimeType, &a.FileSize, &a.CreatedAt)
		attachments = append(attachments, a)
	}

	c.JSON(http.StatusOK, gin.H{"attachments": attachments})
}

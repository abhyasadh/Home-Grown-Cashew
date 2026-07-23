package auth

import (
	"cashew-server/internal/database"
	"net/http"

	"github.com/gin-gonic/gin"
)

type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=50"`
	Password string `json:"password" binding:"required,min=6"`
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func HasUsers() bool {
	var count int
	database.GetDB().QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
	return count > 0
}

func Register(c *gin.Context) {
	if HasUsers() {
		c.JSON(http.StatusConflict, gin.H{"error": "admin user already exists"})
		return
	}

	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	hash, err := HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to hash password"})
		return
	}

	id := GenerateID()
	_, err = database.GetDB().Exec(
		"INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)",
		id, req.Username, hash,
	)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "username already exists"})
		return
	}

	token, err := GenerateToken(id, req.Username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"token":    token,
		"userId":   id,
		"username": req.Username,
	})
}

func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var id, hash string
	err := database.GetDB().QueryRow(
		"SELECT id, password_hash FROM users WHERE username = ?", req.Username,
	).Scan(&id, &hash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	if !CheckPassword(req.Password, hash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	var username string
	database.GetDB().QueryRow("SELECT username FROM users WHERE id = ?", id).Scan(&username)

	token, err := GenerateToken(id, username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":    token,
		"userId":   id,
		"username": username,
	})
}

func GetMe(c *gin.Context) {
	userID := c.GetString("userID")
	username := c.GetString("username")
	c.JSON(http.StatusOK, gin.H{
		"userId":   userID,
		"username": username,
	})
}

func Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"hasUser": HasUsers(),
	})
}

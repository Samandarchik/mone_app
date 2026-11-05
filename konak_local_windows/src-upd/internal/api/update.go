package api

import (
	"crypto/subtle"
	"net/http"
	"os"
	"path/filepath"
)

// Avto-yangilanish artefaktlari (bulut tomoni).
//
// scripts/deploy-cloud.sh har deploy'da Windows binarini ham cross-compile
// qilib `artifacts/` papkaga qo'yadi:
//   - server-windows-amd64.exe — local master uchun yangi binar
//   - windows.json             — {version, build_unix, sha256, size}
//
// Local (Windows) node internal/update orqali shu endpointlarni so'rab,
// yangi build chiqqanini bilib oladi va o'zini o'zi yangilaydi.
// Token — SYNC_TOKEN bilan bir xil: binar butun tizimni almashtirgani uchun
// uni faqat sync huquqi bor node yuklab olishi kerak.
var (
	updateArtifactsDir = "./artifacts"
	updateToken        = ""
)

func ConfigureUpdates(dir, token string) {
	if dir != "" {
		updateArtifactsDir = dir
	}
	updateToken = token
}

func updateAuthorized(r *http.Request) bool {
	given := r.URL.Query().Get("token")
	// ServePeer bilan bir xil doimiy vaqtli solishtirish — javob vaqti
	// orqali tokenni belgima-belgi topib bo'lmasin.
	return updateToken != "" &&
		subtle.ConstantTimeCompare([]byte(given), []byte(updateToken)) == 1
}

// GET /api/update/windows?token=... — artefakt metadatasi (windows.json).
func handleUpdateWindowsInfo(w http.ResponseWriter, r *http.Request) {
	if !updateAuthorized(r) {
		jsonError(w, 401, "unauthorized", "token noto'g'ri")
		return
	}
	data, err := os.ReadFile(filepath.Join(updateArtifactsDir, "windows.json"))
	if err != nil {
		jsonError(w, 404, "no_artifact", "windows artefakti hali build qilinmagan")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(200)
	w.Write(data)
}

// GET /api/update/windows/download?token=... — binarning o'zi.
func handleUpdateWindowsDownload(w http.ResponseWriter, r *http.Request) {
	if !updateAuthorized(r) {
		jsonError(w, 401, "unauthorized", "token noto'g'ri")
		return
	}
	http.ServeFile(w, r, filepath.Join(updateArtifactsDir, "server-windows-amd64.exe"))
}

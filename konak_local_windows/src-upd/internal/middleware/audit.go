package middleware

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/audit"
)

const maxAuditBody = 1 << 20

type auditResponseWriter struct {
	http.ResponseWriter
	status int
	body   bytes.Buffer
}

func (w *auditResponseWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *auditResponseWriter) Write(data []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	if w.body.Len() < maxAuditBody {
		remaining := maxAuditBody - w.body.Len()
		if len(data) < remaining {
			remaining = len(data)
		}
		_, _ = w.body.Write(data[:remaining])
	}
	return w.ResponseWriter.Write(data)
}

func AuditMutations(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead ||
			r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}

		var requestBody []byte
		if !strings.HasPrefix(r.Header.Get("Content-Type"), "multipart/") && r.Body != nil {
			requestBody, _ = io.ReadAll(io.LimitReader(r.Body, maxAuditBody))
			r.Body = io.NopCloser(bytes.NewReader(requestBody))
		}

		capture := &auditResponseWriter{ResponseWriter: w}
		started := time.Now()
		next.ServeHTTP(capture, r)

		claims := GetUser(r.Context())
		if claims == nil {
			return
		}
		route := chi.RouteContext(r.Context()).RoutePattern()
		if route == "" {
			route = r.URL.Path
		}
		entity, entityID := auditEntity(route, r)
		status := capture.status
		if status == 0 {
			status = http.StatusOK
		}
		actorID := claims.UserID
		entry := audit.Entry{
			ActorID:   &actorID,
			ActorName: claims.Name,
			ActorRole: claims.Role,
			Action:    strings.ToLower(r.Method),
			Entity:    entity,
			EntityID:  entityID,
			Request:   audit.SanitizeJSON(requestBody),
			Response:  audit.SanitizeJSON(capture.body.Bytes()),
			Metadata: map[string]interface{}{
				"route":       route,
				"status":      status,
				"duration_ms": time.Since(started).Milliseconds(),
			},
			IP: remoteIP(r),
		}
		go audit.Log(context.Background(), entry)
	})
}

func auditEntity(route string, r *http.Request) (string, string) {
	clean := strings.Trim(route, "/")
	parts := strings.Split(clean, "/")
	if len(parts) > 0 && parts[0] == "api" {
		parts = parts[1:]
	}
	entity := "api"
	if len(parts) > 0 {
		entity = strings.TrimSuffix(parts[0], "s")
	}
	entityID := ""
	for _, key := range []string{"id", "product_id"} {
		if value := chi.URLParam(r, key); value != "" {
			entityID = value
			break
		}
	}
	return entity, entityID
}

func remoteIP(r *http.Request) string { return ClientIP(r) }

// TrustProxyHeaders — reverse-proxy orqasida ishlaganda `X-Forwarded-For` ga
// ishonish kerakmi. Faqat sozlamadan yoqiladi: to'g'ridan-to'g'ri ochiq
// serverda bu sarlavhani istalgan kishi soxtalashtirib, kirish urinishlari
// chegarasini chetlab o'ta olardi.
var TrustProxyHeaders bool

// ClientIP — mijozning haqiqiy IP manzili.
//
// NEGA KERAK: bulut node'i reverse-proxy orqasida turadi va u yerda hamma
// so'rov bir xil `RemoteAddr` bilan keladi. Natijada kirish urinishlari
// chegarasi butun internetga umumiy bo'lib qolardi — begona odam 5 marta
// noto'g'ri PIN kiritsa, BARCHA xodimlar 5 daqiqaga tizimga kira olmasdi.
func ClientIP(r *http.Request) string {
	if TrustProxyHeaders {
		if v := r.Header.Get("X-Forwarded-For"); v != "" {
			// Ro'yxatdagi BIRINCHI manzil — asl mijoz.
			if i := strings.IndexByte(v, ','); i > 0 {
				v = v[:i]
			}
			if ip := strings.TrimSpace(v); ip != "" {
				return ip
			}
		}
		if v := strings.TrimSpace(r.Header.Get("X-Real-IP")); v != "" {
			return v
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func (w *auditResponseWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

func (w *auditResponseWriter) Status() int {
	if w.status == 0 {
		return http.StatusOK
	}
	return w.status
}

func (w *auditResponseWriter) Size() int {
	return w.body.Len()
}

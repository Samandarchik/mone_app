package version

import "strconv"

// Build vaqtida ldflags bilan to'ldiriladi (scripts/deploy-cloud.sh):
//
//	-X konak-local/internal/version.Version=260820.1710-8ab463f
//	-X konak-local/internal/version.BuildUnixStr=1755700000
//
// Oddiy `go build` (ldflagssiz) — "dev"/0: bunday binar har qanday haqiqiy
// artefaktni "yangiroq" deb qabul qiladi va o'zini yangilab oladi.
var (
	Version      = "dev"
	BuildUnixStr = "0"
)

// BuildUnix — binar qachon build qilingani (unix soniya). Yangilanish
// solishtiruvi versiya satri emas, AYNAN shu son bilan qilinadi: satr
// formatini o'zgartirish avto-yangilanishni buzmasin.
func BuildUnix() int64 {
	n, _ := strconv.ParseInt(BuildUnixStr, 10, 64)
	return n
}

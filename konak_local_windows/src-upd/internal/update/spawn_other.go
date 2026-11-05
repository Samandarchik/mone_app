//go:build !windows

package update

import "errors"

// Avto-yangilanish faqat Windows'da (Start ham faqat u yerda yoqadi) —
// bu stub boshqa OS'larda build o'tishi uchun turibdi.
func spawnDetached(string) error {
	return errors.New("avto-yangilanish faqat windows'da ishlaydi")
}

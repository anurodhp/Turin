/* TurinIcons: the sidebar's colourful icons, drawn rather than shipped as pictures (they stay sharp at any size and need
 * no files): a rounded tile with a gradient and a white symbol, as System Settings draws them. Also the Wi-Fi fan and
 * the padlock the Wi-Fi pane's network list uses (Naples' drawings, NaplesWifi.m). */
#import <AppKit/AppKit.h>

typedef enum { TurinIconWifi, TurinIconNetwork, TurinIconDateTime, TurinIconBackground, TurinIconUsers } TurinIconKind;

/* r is in an unflipped view */
void TurinDrawIcon(TurinIconKind kind, NSRect r);
/* the Wi-Fi fan in r (about 18 x 14): `bars` 0-3 arcs drawn solid, the rest faint; `off` adds a slash */
void TurinDrawWifiFan(NSRect r, int bars, BOOL off, NSColor *color);
int TurinWifiBars(int rssi);	/* 3 at -60 dBm or better, 2 at -72 or better, else 1 */
void TurinDrawLock(NSPoint at, NSColor *color);	/* 8 x 9, bottom-left at `at` */
/* a round badge with the initials of `name` on a colour picked from it (the Users pane's pictures) */
void TurinDrawAvatar(NSRect r, NSString *name);

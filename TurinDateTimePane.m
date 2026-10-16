#import "TurinDateTimePane.h"
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static NSString *const monthNames[] = { @"January", @"February", @"March", @"April", @"May", @"June", @"July", @"August",
                                        @"September", @"October", @"November", @"December" };
static NSString *const dayNames[] = { @"Sunday", @"Monday", @"Tuesday", @"Wednesday", @"Thursday", @"Friday", @"Saturday" };

/* The zone database and the default zone of this libc: the image's Libc is the embedded build, whose tzfile.h puts them
 * under /var/db/timezone (third_party/Libc/stdtime/FreeBSD/tzfile.h). gnustep-base reads /etc/localtime
 * (NSTimeZone.m SYSTEM_TIME_FILE), so both links are written. */
#define ZoneDir     "/var/db/timezone/zoneinfo"
#define ZoneDefault "/var/db/timezone/localtime"
#define EtcLocaltime "/etc/localtime"
#define HwClockFile "/var/db/fake-hwclock"

static int
daysInMonth(int y, int m)
{
	static const int n[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
	if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) return 29;
	return n[m - 1];
}

/* 0 = Sunday */
static int
weekdayOf(int y, int m, int d)
{
	struct tm t;
	memset(&t, 0, sizeof t);
	t.tm_year = y - 1900; t.tm_mon = m - 1; t.tm_mday = d; t.tm_hour = 12; t.tm_isdst = -1;
	mktime(&t);
	return t.tm_wday;
}

static struct tm
nowTM(void)
{
	time_t t = time(NULL);
	struct tm tm;
	localtime_r(&t, &tm);
	return tm;
}

/* ---- the analog clock ---- */

@interface TurinClockView : NSView { TurinDateTimePane *pane; }
- (id) initWithFrame: (NSRect)f pane: (TurinDateTimePane *)p;
@end

@implementation TurinClockView

- (id) initWithFrame: (NSRect)f pane: (TurinDateTimePane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }

static void
hand(NSPoint c, CGFloat angle, CGFloat len, CGFloat width, NSColor *color)
{
	NSBezierPath *p = [NSBezierPath bezierPath];
	[color set];
	[p setLineWidth: width];
	[p setLineCapStyle: NSRoundLineCapStyle];
	[p moveToPoint: NSMakePoint(c.x - sin(angle) * len * 0.12, c.y - cos(angle) * len * 0.12)];
	[p lineToPoint: NSMakePoint(c.x + sin(angle) * len, c.y + cos(angle) * len)];
	[p stroke];
}

- (void) drawRect: (NSRect)dirty
{
	NSRect b = NSInsetRect([self bounds], 4, 4);
	CGFloat r = MIN(b.size.width, b.size.height) / 2;
	NSPoint c = NSMakePoint(NSMidX(b), NSMidY(b));
	struct tm t = [pane shownTime];
	NSDictionary *na = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: floor(r * 0.16)], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0.15 alpha: 1], NSForegroundColorAttributeName, nil];
	int i;
	NSGradient *g = [[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 0.90 alpha: 1]
	                                               endingColor: [NSColor whiteColor]] autorelease];
	NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect: NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r)];
	[g drawInBezierPath: face angle: 90];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.25] set];
	[face setLineWidth: 1.5];
	[face stroke];
	for (i = 0; i < 60; i++) {
		CGFloat a = i * M_PI / 30, in = i % 5 ? r * 0.9 : r * 0.84;
		NSBezierPath *p = [NSBezierPath bezierPath];
		[[NSColor colorWithCalibratedWhite: 0 alpha: i % 5 ? 0.3 : 0.7] set];
		[p setLineWidth: i % 5 ? 0.8 : 1.6];
		[p moveToPoint: NSMakePoint(c.x + sin(a) * in, c.y + cos(a) * in)];
		[p lineToPoint: NSMakePoint(c.x + sin(a) * r * 0.95, c.y + cos(a) * r * 0.95)];
		[p stroke];
	}
	for (i = 1; i <= 12; i++) {
		CGFloat a = i * M_PI / 6;
		NSString *s = [NSString stringWithFormat: @"%d", i];
		NSSize sz = [s sizeWithAttributes: na];
		[s drawAtPoint: NSMakePoint(c.x + sin(a) * r * 0.7 - sz.width / 2, c.y + cos(a) * r * 0.7 - sz.height / 2) withAttributes: na];
	}
	hand(c, ((t.tm_hour % 12) + t.tm_min / 60.0) * M_PI / 6, r * 0.5, 4, [NSColor colorWithCalibratedWhite: 0.12 alpha: 1]);
	hand(c, (t.tm_min + t.tm_sec / 60.0) * M_PI / 30, r * 0.74, 3, [NSColor colorWithCalibratedWhite: 0.12 alpha: 1]);
	if (![pane editing])
		hand(c, t.tm_sec * M_PI / 30, r * 0.8, 1.2, [NSColor colorWithCalibratedRed: 0.92 green: 0.4 blue: 0.1 alpha: 1]);
	[[NSColor colorWithCalibratedRed: 0.92 green: 0.4 blue: 0.1 alpha: 1] set];
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(c.x - 3, c.y - 3, 6, 6)] fill];
}

@end

/* ---- the month calendar ---- */

@interface TurinCalendarView : NSView {
	TurinDateTimePane *pane;
	int shownYear, shownMonth;	/* the month on screen, moved by the arrows */
}
- (id) initWithFrame: (NSRect)f pane: (TurinDateTimePane *)p;
- (void) showMonthOf: (int)y month: (int)m;
@end

enum { CalHeaderH = 26, CalNamesH = 18, CellW = 32, CellH = 22 };

@implementation TurinCalendarView

- (id) initWithFrame: (NSRect)f pane: (TurinDateTimePane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (void) showMonthOf: (int)y month: (int)m { shownYear = y; shownMonth = m; [self setNeedsDisplay: YES]; }

- (NSRect) prevRect { return NSMakeRect(4, NSHeight([self bounds]) - CalHeaderH + 3, 22, 20); }
- (NSRect) nextRect { return NSMakeRect(7 * CellW - 22, NSHeight([self bounds]) - CalHeaderH + 3, 22, 20); }

- (NSRect) cellFor: (int)d
{
	int first = weekdayOf(shownYear, shownMonth, 1), idx = first + d - 1;
	CGFloat top = NSHeight([self bounds]) - CalHeaderH - CalNamesH;
	return NSMakeRect((idx % 7) * CellW, top - (idx / 7 + 1) * CellH, CellW, CellH);
}

static void
arrow(NSRect r, BOOL left)
{
	NSBezierPath *p = [NSBezierPath bezierPath];
	CGFloat x = NSMidX(r), y = NSMidY(r);
	[[NSColor colorWithCalibratedWhite: 0.25 alpha: 1] set];
	[p setLineWidth: 2];
	[p setLineCapStyle: NSRoundLineCapStyle];
	[p moveToPoint: NSMakePoint(x + (left ? 3 : -3), y + 5)];
	[p lineToPoint: NSMakePoint(x + (left ? -3 : 3), y)];
	[p lineToPoint: NSMakePoint(x + (left ? 3 : -3), y - 5)];
	[p stroke];
}

- (void) drawRect: (NSRect)dirty
{
	NSRect b = [self bounds];
	struct tm now = nowTM();
	NSString *title = [NSString stringWithFormat: @"%@ %d", monthNames[shownMonth - 1], shownYear];
	NSDictionary *ta = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 13], NSFontAttributeName,
	                    [NSColor blackColor], NSForegroundColorAttributeName, nil];
	NSDictionary *wa = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 10], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0 alpha: 0.45], NSForegroundColorAttributeName, nil];
	NSSize sz = [title sizeWithAttributes: ta];
	int d, i, n = daysInMonth(shownYear, shownMonth);
	[title drawAtPoint: NSMakePoint(7 * CellW / 2.0 - sz.width / 2, NSHeight(b) - CalHeaderH + 5) withAttributes: ta];
	arrow([self prevRect], YES);
	arrow([self nextRect], NO);
	for (i = 0; i < 7; i++) {
		NSString *s = [dayNames[i] substringToIndex: 2];
		NSSize ws = [s sizeWithAttributes: wa];
		[s drawAtPoint: NSMakePoint(i * CellW + CellW / 2.0 - ws.width / 2, NSHeight(b) - CalHeaderH - CalNamesH + 3) withAttributes: wa];
	}
	for (d = 1; d <= n; d++) {
		NSRect c = [self cellFor: d];
		BOOL chosen = shownYear == [pane year] && shownMonth == [pane month] && d == [pane day];
		BOOL today = shownYear == now.tm_year + 1900 && shownMonth == now.tm_mon + 1 && d == now.tm_mday;
		NSString *s = [NSString stringWithFormat: @"%d", d];
		NSDictionary *da = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 12], NSFontAttributeName,
		                    chosen ? [NSColor whiteColor] : today ? [NSColor colorWithCalibratedRed: 0.9 green: 0.25 blue: 0.2 alpha: 1]
		                           : [NSColor colorWithCalibratedWhite: 0.1 alpha: 1], NSForegroundColorAttributeName, nil];
		NSSize ds = [s sizeWithAttributes: da];
		NSRect dot = NSMakeRect(NSMidX(c) - 11, NSMidY(c) - 10, 22, 20);
		if (chosen) {
			[(today ? [NSColor colorWithCalibratedRed: 0.9 green: 0.25 blue: 0.2 alpha: 1] : TurinAccent()) set];
			[[NSBezierPath bezierPathWithRoundedRect: dot xRadius: 10 yRadius: 10] fill];
		}
		[s drawAtPoint: NSMakePoint(NSMidX(c) - ds.width / 2, NSMidY(c) - ds.height / 2) withAttributes: da];
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
	int d, n = daysInMonth(shownYear, shownMonth);
	if (NSPointInRect(p, NSInsetRect([self prevRect], -4, -4))) {
		if (--shownMonth < 1) { shownMonth = 12; shownYear--; }
		[self setNeedsDisplay: YES];
		return;
	}
	if (NSPointInRect(p, NSInsetRect([self nextRect], -4, -4))) {
		if (++shownMonth > 12) { shownMonth = 1; shownYear++; }
		[self setNeedsDisplay: YES];
		return;
	}
	for (d = 1; d <= n; d++)
		if (NSPointInRect(p, [self cellFor: d])) { [pane setYear: shownYear month: shownMonth day: d]; return; }
}

@end

/* ---- locales ---- */

/* id, the name shown, the GNUstep language name (the .lproj names gnustep-gui and apps ship) */
static NSString *const locales[][3] = {
	{ @"en_US", @"English (United States)", @"English" }, { @"en_GB", @"English (United Kingdom)", @"English" },
	{ @"en_CA", @"English (Canada)", @"English" }, { @"en_AU", @"English (Australia)", @"English" },
	{ @"en_IN", @"English (India)", @"English" }, { @"fr_FR", @"French (France)", @"French" },
	{ @"fr_CA", @"French (Canada)", @"French" }, { @"de_DE", @"German (Germany)", @"German" },
	{ @"de_CH", @"German (Switzerland)", @"German" }, { @"es_ES", @"Spanish (Spain)", @"Spanish" },
	{ @"es_MX", @"Spanish (Mexico)", @"Spanish" }, { @"it_IT", @"Italian (Italy)", @"Italian" },
	{ @"pt_PT", @"Portuguese (Portugal)", @"Portuguese" }, { @"pt_BR", @"Portuguese (Brazil)", @"BrazilPortuguese" },
	{ @"nl_NL", @"Dutch (Netherlands)", @"Dutch" }, { @"sv_SE", @"Swedish (Sweden)", @"Swedish" },
	{ @"nb_NO", @"Norwegian (Norway)", @"Norwegian" }, { @"da_DK", @"Danish (Denmark)", @"Danish" },
	{ @"fi_FI", @"Finnish (Finland)", @"Finnish" }, { @"pl_PL", @"Polish (Poland)", @"Polish" },
	{ @"cs_CZ", @"Czech (Czechia)", @"Czech" }, { @"hu_HU", @"Hungarian (Hungary)", @"Hungarian" },
	{ @"ru_RU", @"Russian (Russia)", @"Russian" }, { @"uk_UA", @"Ukrainian (Ukraine)", @"Ukrainian" },
	{ @"tr_TR", @"Turkish (Turkey)", @"Turkish" }, { @"el_GR", @"Greek (Greece)", @"Greek" },
	{ @"he_IL", @"Hebrew (Israel)", @"Hebrew" }, { @"ar_SA", @"Arabic (Saudi Arabia)", @"Arabic" },
	{ @"hi_IN", @"Hindi (India)", @"Hindi" }, { @"ne_NP", @"Nepali (Nepal)", @"Nepali" },
	{ @"zh_CN", @"Chinese (China)", @"SimplifiedChinese" }, { @"zh_TW", @"Chinese (Taiwan)", @"TraditionalChinese" },
	{ @"ja_JP", @"Japanese (Japan)", @"Japanese" }, { @"ko_KR", @"Korean (South Korea)", @"Korean" },
};
#define NLocales (sizeof locales / sizeof locales[0])

/* ---- the pane ---- */

@implementation TurinDateTimePane

- (NSString *) title { return @"Date & Time"; }
- (TurinIconKind) icon { return TurinIconDateTime; }
- (BOOL) editing { return editing; }
- (int) year { return year; }
- (int) month { return month; }
- (int) day { return day; }

- (void) dealloc
{
	[clockView release]; [calendarView release]; [timeField release]; [dateLabel release]; [syncLabel release];
	[dateMessage release]; [setButton release]; [revertButton release]; [zones release]; [regionPopup release];
	[cityPopup release]; [zoneLabel release]; [zoneMessage release]; [zoneButton release]; [localePopup release];
	[localeLabel release]; [localeButton release];
	[super dealloc];
}

/* the time the clock shows: now, or the chosen date at the time in the field */
- (struct tm) shownTime
{
	struct tm t = nowTM();
	int h, m, s = 0;
	if (editing && sscanf([[timeField stringValue] UTF8String], "%d:%d:%d", &h, &m, &s) >= 2) {
		t.tm_hour = h; t.tm_min = m; t.tm_sec = s;
	}
	return t;
}

- (void) showNow
{
	struct tm t = nowTM();
	year = t.tm_year + 1900; month = t.tm_mon + 1; day = t.tm_mday;
	[timeField setStringValue: [NSString stringWithFormat: @"%02d:%02d:%02d", t.tm_hour, t.tm_min, t.tm_sec]];
}

- (void) updateDateLabel
{
	[dateLabel setStringValue: [NSString stringWithFormat: @"%@, %d %@ %d", dayNames[weekdayOf(year, month, day)], day,
	                            monthNames[month - 1], year]];
	[setButton setEnabled: editing && TurinIsRoot()];
	[revertButton setEnabled: editing];
}

- (void) startEditing
{
	if (editing) return;
	editing = YES;
	[dateMessage setStringValue: @""];
	[self updateDateLabel];
}

- (void) setYear: (int)y month: (int)m day: (int)d
{
	[self startEditing];
	year = y; month = m; day = d;
	[self updateDateLabel];
	[calendarView setNeedsDisplay: YES];
	[clockView setNeedsDisplay: YES];
}

- (void) controlTextDidChange: (NSNotification *)n
{
	if ([n object] == timeField) { [self startEditing]; [clockView setNeedsDisplay: YES]; }
}

- (void) tick
{
	if (!editing) {
		struct tm t = nowTM();
		BOOL dayChanged = year != t.tm_year + 1900 || month != t.tm_mon + 1 || day != t.tm_mday;
		[self showNow];
		if (dayChanged) { [self updateDateLabel]; [calendarView setNeedsDisplay: YES]; }
	}
	[clockView setNeedsDisplay: YES];
}

static BOOL
processRunning(const char *name)
{
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
	size_t len = 0, i, n;
	struct kinfo_proc *kp;
	BOOL found = NO;
	if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) return NO;
	len += len / 4;
	if (!(kp = malloc(len))) return NO;
	if (sysctl(mib, 4, kp, &len, NULL, 0) == 0) {
		n = len / sizeof *kp;
		for (i = 0; i < n && !found; i++) found = !strcmp(kp[i].kp_proc.p_comm, name);
	}
	free(kp);
	return found;
}

- (void) updateSync
{
	[syncLabel setStringValue: processRunning("chronyd")
	    ? @"chronyd is keeping the clock in step with time servers; it will correct a time set by hand."
	    : @"chronyd is not running. The clock is kept across restarts by fake-hwclock."];
}

- (void) applyDate: (id)sender
{
	struct tm t;
	struct timeval tv;
	int h = 0, m = 0, s = 0, fd, k = sscanf([[timeField stringValue] UTF8String], "%d:%d:%d", &h, &m, &s);
	if (k < 2 || h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) {
		[dateMessage setStringValue: @"Enter the time as HH:MM or HH:MM:SS (24-hour)."];
		return;
	}
	memset(&t, 0, sizeof t);
	t.tm_year = year - 1900; t.tm_mon = month - 1; t.tm_mday = day;
	t.tm_hour = h; t.tm_min = m; t.tm_sec = k == 3 ? s : 0; t.tm_isdst = -1;
	tv.tv_sec = mktime(&t);
	tv.tv_usec = 0;
	if (tv.tv_sec == (time_t)-1 || settimeofday(&tv, NULL) != 0) {
		[dateMessage setStringValue: [NSString stringWithFormat: @"The clock could not be set: %s.", strerror(errno)]];
		return;
	}
	/* fake-hwclock restores this file at boot (forward only), so the new time survives a restart */
	unlink(HwClockFile ".new");
	if ((fd = open(HwClockFile ".new", O_WRONLY | O_CREAT | O_EXCL, 0644)) >= 0) {
		char buf[32];
		int n = snprintf(buf, sizeof buf, "%ld\n", (long)tv.tv_sec);
		if (write(fd, buf, n) == n) { close(fd); rename(HwClockFile ".new", HwClockFile); }
		else { close(fd); unlink(HwClockFile ".new"); }
	}
	editing = NO;
	[dateMessage setStringValue: @"The date and time were set."];
	[self tick];
	[self updateDateLabel];
	[(TurinCalendarView *)calendarView showMonthOf: year month: month];
}

- (void) revertDate: (id)sender
{
	editing = NO;
	[dateMessage setStringValue: @""];
	[self showNow];
	[self updateDateLabel];
	[(TurinCalendarView *)calendarView showMonthOf: year month: month];
	[clockView setNeedsDisplay: YES];
}

/* ---- time zone ---- */

static NSString *
zoneDir(void)
{
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath: @ZoneDir "/zone.tab"]) return @ZoneDir;
	if ([fm fileExistsAtPath: @"/usr/share/zoneinfo/zone.tab"]) return @"/usr/share/zoneinfo";
	return @ZoneDir;
}

/* region -> sorted zones, from zone.tab (code, coordinates, zone, comment); UTC on its own */
static NSDictionary *
loadZones(void)
{
	NSMutableDictionary *by = [NSMutableDictionary dictionary];
	NSString *dir = zoneDir(), *tab, *line, *z;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSEnumerator *e;
	tab = [NSString stringWithContentsOfFile: [dir stringByAppendingPathComponent: @"zone.tab"] encoding: NSUTF8StringEncoding error: NULL];
	for (line in [tab componentsSeparatedByString: @"\n"]) {
		NSArray *f = [line componentsSeparatedByString: @"\t"];
		NSRange slash;
		NSMutableArray *list;
		if ([line hasPrefix: @"#"] || [f count] < 3) continue;
		z = [f objectAtIndex: 2];
		slash = [z rangeOfString: @"/"];
		if (slash.location == NSNotFound) continue;
		if (![fm fileExistsAtPath: [dir stringByAppendingPathComponent: z]]) continue;
		if (!(list = [by objectForKey: [z substringToIndex: slash.location]])) {
			list = [NSMutableArray array];
			[by setObject: list forKey: [z substringToIndex: slash.location]];
		}
		[list addObject: z];
	}
	e = [[by allKeys] objectEnumerator];
	while ((z = [e nextObject])) [[by objectForKey: z] sortUsingSelector: @selector(compare:)];
	[by setObject: [NSMutableArray arrayWithObject: @"UTC"] forKey: @"UTC"];
	return by;
}

/* the zone the system uses: the target of the default link, else UTC (the image ships a plain copy of UTC there) */
static NSString *
currentZone(void)
{
	char buf[1024];
	ssize_t n = readlink(ZoneDefault, buf, sizeof buf - 1);
	NSString *p;
	NSRange r;
	if (n <= 0) n = readlink(EtcLocaltime, buf, sizeof buf - 1);
	if (n <= 0) return @"UTC";
	buf[n] = 0;
	p = [NSString stringWithUTF8String: buf];
	r = [p rangeOfString: @"zoneinfo/"];
	return r.location == NSNotFound ? [p lastPathComponent] : [p substringFromIndex: NSMaxRange(r)];
}

static NSString *
cityName(NSString *zone)
{
	NSRange slash = [zone rangeOfString: @"/"];
	NSString *c = slash.location == NSNotFound ? zone : [zone substringFromIndex: NSMaxRange(slash)];
	c = [c stringByReplacingOccurrencesOfString: @"_" withString: @" "];
	return [c stringByReplacingOccurrencesOfString: @"/" withString: @" – "];
}

- (void) fillCities
{
	NSArray *list = [zones objectForKey: [regionPopup titleOfSelectedItem]];
	NSString *z;
	[cityPopup removeAllItems];
	for (z in list) {
		[cityPopup addItemWithTitle: cityName(z)];
		[[cityPopup lastItem] setRepresentedObject: z];
	}
}

- (void) regionChanged: (id)sender { [self fillCities]; [zoneMessage setStringValue: @""]; }

- (void) showZone
{
	NSString *z = currentZone();
	time_t now = time(NULL);
	struct tm lt;
	long off;
	tzset();
	localtime_r(&now, &lt);
	off = lt.tm_gmtoff;
	[zoneLabel setStringValue: [NSString stringWithFormat: @"Current time zone: %@ (%s, UTC%c%02ld:%02ld)", z, lt.tm_zone ? lt.tm_zone : "",
	                            off < 0 ? '-' : '+', labs(off) / 3600, (labs(off) % 3600) / 60]];
	{	/* select it in the popups */
		NSRange slash = [z rangeOfString: @"/"];
		NSString *region = slash.location == NSNotFound ? @"UTC" : [z substringToIndex: slash.location];
		NSInteger i;
		if ([regionPopup indexOfItemWithTitle: region] >= 0) {
			[regionPopup selectItemWithTitle: region];
			[self fillCities];
			for (i = 0; i < [cityPopup numberOfItems]; i++)
				if ([[[cityPopup itemAtIndex: i] representedObject] isEqual: z]) [cityPopup selectItemAtIndex: i];
		}
	}
}

static BOOL
relink(const char *link, const char *target)
{
	char tmp[1100];
	snprintf(tmp, sizeof tmp, "%s.turin", link);
	unlink(tmp);
	if (symlink(target, tmp) != 0) return NO;
	if (rename(tmp, link) != 0) { unlink(tmp); return NO; }
	return YES;
}

- (void) applyZone: (id)sender
{
	NSString *z = [[cityPopup selectedItem] representedObject];
	NSString *path = [zoneDir() stringByAppendingPathComponent: z];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *g;
	if (!z || ![[NSFileManager defaultManager] fileExistsAtPath: path]) {
		[zoneMessage setStringValue: @"That time zone is not installed."];
		return;
	}
	if (!relink(ZoneDefault, [path fileSystemRepresentation])) {
		[zoneMessage setStringValue: [NSString stringWithFormat: @"The time zone could not be set: %s.", strerror(errno)]];
		return;
	}
	relink(EtcLocaltime, [path fileSystemRepresentation]);
	/* a per-user "Local Time Zone" default would override the system's zone in GNUstep apps (NSTimeZone.m's order) */
	g = [[[d persistentDomainForName: NSGlobalDomain] mutableCopy] autorelease];
	if ([g objectForKey: @"Local Time Zone"]) {
		[g removeObjectForKey: @"Local Time Zone"];
		[d setPersistentDomain: g forName: NSGlobalDomain];
		[d synchronize];
	}
	tzset();
	[NSTimeZone resetSystemTimeZone];
	[zoneMessage setStringValue: @"Set. Applications opened from now on use the new time zone."];
	[self showZone];
	[self tick];
}

/* ---- locale ---- */

- (void) showLocale
{
	NSString *cur = [[NSUserDefaults standardUserDefaults] stringForKey: @"Locale"];
	NSUInteger i;
	if (!cur) cur = @"en_US";
	for (i = 0; i < NLocales; i++)
		if ([locales[i][0] isEqual: cur]) [localePopup selectItemAtIndex: i];
	[localeLabel setStringValue: [NSString stringWithFormat: @"Current region: %@", cur]];
}

- (void) applyLocale: (id)sender
{
	NSInteger i = [localePopup indexOfSelectedItem];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *g;
	NSMutableArray *langs;
	if (i < 0 || i >= (NSInteger)NLocales) return;
	g = [[[d persistentDomainForName: NSGlobalDomain] mutableCopy] autorelease];
	if (!g) g = [NSMutableDictionary dictionary];
	[g setObject: locales[i][0] forKey: @"Locale"];
	/* the chosen language first, English after it as the fallback every app has */
	langs = [NSMutableArray arrayWithObject: locales[i][2]];
	if (![locales[i][2] isEqual: @"English"]) [langs addObject: @"English"];
	[g setObject: langs forKey: @"NSLanguages"];
	[d setPersistentDomain: g forName: NSGlobalDomain];
	[d synchronize];
	[self showLocale];
	[localeLabel setStringValue: [NSString stringWithFormat: @"Current region: %@. Applications opened from now on use it.", locales[i][0]]];
}

/* ---- layout ---- */

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth;
	NSArray *regions;
	NSString *r;
	NSUInteger i;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 230, W - 40, 270)],
	    [NSValue valueWithRect: NSMakeRect(20, 116, W - 40, 104)],
	    [NSValue valueWithRect: NSMakeRect(20, 16, W - 40, 90)], nil]];

	/* date and time */
	clockView = [[TurinClockView alloc] initWithFrame: NSMakeRect(44, 304, 166, 166) pane: self];
	[v addSubview: clockView];
	calendarView = [[TurinCalendarView alloc] initWithFrame: NSMakeRect(W - 36 - 7 * CellW, 314, 7 * CellW,
	                                                                     CalHeaderH + CalNamesH + 6 * CellH) pane: self];
	[v addSubview: calendarView];
	dateLabel = [TurinLabel(NSMakeRect(36, 474, 220, 20), @"", 13, YES) retain];
	[v addSubview: dateLabel];
	[v addSubview: TurinLabel(NSMakeRect(232, 284, 40, 20), @"Time:", 12, NO)];
	timeField = [TurinField(NSMakeRect(274, 282, 80, 24), @"") retain];
	[timeField setDelegate: self];
	[v addSubview: timeField];
	revertButton = [TurinButton(NSMakeRect(W - 224, 280, 90, 26), @"Revert", self, @selector(revertDate:)) retain];
	setButton = [TurinButton(NSMakeRect(W - 126, 280, 90, 26), @"Set", self, @selector(applyDate:)) retain];
	[v addSubview: revertButton];
	[v addSubview: setButton];
	syncLabel = [TurinLabel(NSMakeRect(36, 256, W - 72, 16), @"", 11, NO) retain];
	[syncLabel setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
	[v addSubview: syncLabel];
	dateMessage = [TurinLabel(NSMakeRect(36, 238, W - 72, 16), TurinIsRoot() ? @"" : @"Setting the clock needs the root account.", 11, NO) retain];
	[dateMessage setTextColor: [NSColor colorWithCalibratedRed: 0.75 green: 0.2 blue: 0.1 alpha: 1]];
	[v addSubview: dateMessage];

	/* time zone */
	[v addSubview: TurinLabel(NSMakeRect(36, 192, 200, 18), @"Time Zone", 13, YES)];
	zones = [loadZones() retain];
	[v addSubview: TurinLabel(NSMakeRect(36, 162, 60, 18), @"Region:", 12, NO)];
	regionPopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(96, 158, 150, 26) pullsDown: NO];
	regions = [[zones allKeys] sortedArrayUsingSelector: @selector(compare:)];
	for (r in regions) [regionPopup addItemWithTitle: r];
	[regionPopup setTarget: self];
	[regionPopup setAction: @selector(regionChanged:)];
	[v addSubview: regionPopup];
	[v addSubview: TurinLabel(NSMakeRect(258, 162, 40, 18), @"City:", 12, NO)];
	cityPopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(296, 158, 170, 26) pullsDown: NO];
	[v addSubview: cityPopup];
	zoneButton = [TurinButton(NSMakeRect(W - 112, 158, 76, 26), @"Set", self, @selector(applyZone:)) retain];
	[zoneButton setEnabled: TurinIsRoot()];
	[v addSubview: zoneButton];
	zoneLabel = [TurinLabel(NSMakeRect(36, 136, W - 72, 16), @"", 11, NO) retain];
	[v addSubview: zoneLabel];
	zoneMessage = [TurinLabel(NSMakeRect(36, 120, W - 72, 16), [zones count] < 3
	    ? @"Only UTC is installed on this system (no zone.tab in " ZoneDir ")." : @"", 11, NO) retain];
	[zoneMessage setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
	[v addSubview: zoneMessage];

	/* language and region */
	[v addSubview: TurinLabel(NSMakeRect(36, 78, 200, 18), @"Language & Region", 13, YES)];
	[v addSubview: TurinLabel(NSMakeRect(36, 48, 60, 18), @"Region:", 12, NO)];
	localePopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(96, 44, 250, 26) pullsDown: NO];
	for (i = 0; i < NLocales; i++) [localePopup addItemWithTitle: locales[i][1]];
	[v addSubview: localePopup];
	localeButton = [TurinButton(NSMakeRect(W - 112, 44, 76, 26), @"Set", self, @selector(applyLocale:)) retain];
	[v addSubview: localeButton];
	localeLabel = [TurinLabel(NSMakeRect(36, 24, W - 72, 16), @"", 11, NO) retain];
	[localeLabel setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
	[v addSubview: localeLabel];

	[self showNow];
	[(TurinCalendarView *)calendarView showMonthOf: year month: month];
	[self updateDateLabel];
	[self showZone];
	[self showLocale];
	[self updateSync];
}

- (void) didShow
{
	if (!timer) {
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_source_set_event_handler(timer, ^{ TurinRunOnMain(^{ [self tick]; }); });
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 20);
		dispatch_resume(timer);
	}
	[self updateSync];
	[self showZone];
}

- (void) didHide
{
	if (timer) { dispatch_source_cancel(timer); dispatch_release(timer); timer = NULL; }
}

@end

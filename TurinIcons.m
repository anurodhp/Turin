#import "TurinIcons.h"
#include <math.h>

static NSColor *
rgb(CGFloat r, CGFloat g, CGFloat b)
{
	return [NSColor colorWithCalibratedRed: r green: g blue: b alpha: 1];
}

static void
tile(NSRect r, NSColor *top, NSColor *bottom)
{
	CGFloat rad = r.size.width * 0.23;
	NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: r xRadius: rad yRadius: rad];
	NSGradient *g = [[[NSGradient alloc] initWithStartingColor: bottom endingColor: top] autorelease];
	[g drawInBezierPath: p angle: 90];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.12] set];
	[[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, 0.5, 0.5) xRadius: rad yRadius: rad] stroke];
}

int
TurinWifiBars(int rssi)
{
	return rssi >= -60 ? 3 : rssi >= -72 ? 2 : 1;
}

void
TurinDrawWifiFan(NSRect r, int bars, BOOL off, NSColor *color)
{
	/* a dot and three arcs opening upwards, centred at the bottom middle; the sizes scale with r (18 x 14 is Naples') */
	CGFloat k = r.size.height / 14.0;
	NSPoint c = NSMakePoint(NSMidX(r), NSMinY(r) + 1.5 * k);
	NSColor *faint = [color colorWithAlphaComponent: [color alphaComponent] * 0.28];
	int i;
	[(bars > 0 ? color : faint) set];
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(c.x - 1.6 * k, c.y - 0.4 * k, 3.2 * k, 3.2 * k)] fill];
	for (i = 0; i < 3; i++) {
		NSBezierPath *a = [NSBezierPath bezierPath];
		[(i < bars ? color : faint) set];
		[a setLineWidth: 1.7 * k];
		[a setLineCapStyle: NSRoundLineCapStyle];
		[a appendBezierPathWithArcWithCenter: c radius: (4.6 + 3.8 * i) * k startAngle: 45 endAngle: 135];
		[a stroke];
	}
	if (off) {
		NSBezierPath *s = [NSBezierPath bezierPath];
		[color set];
		[s setLineWidth: 1.5 * k];
		[s setLineCapStyle: NSRoundLineCapStyle];
		[s moveToPoint: NSMakePoint(NSMinX(r) + 2 * k, NSMinY(r) + 1 * k)];
		[s lineToPoint: NSMakePoint(NSMaxX(r) - 2 * k, NSMaxY(r) - 1 * k)];
		[s stroke];
	}
}

void
TurinDrawLock(NSPoint at, NSColor *color)
{
	NSBezierPath *shackle = [NSBezierPath bezierPath];
	[color set];
	NSRectFill(NSMakeRect(at.x, at.y, 8, 6));
	[shackle setLineWidth: 1.3];
	[shackle appendBezierPathWithArcWithCenter: NSMakePoint(at.x + 4, at.y + 6) radius: 2.6 startAngle: 0 endAngle: 180];
	[shackle stroke];
}

static void
globe(NSRect r)
{
	NSRect c = NSInsetRect(r, r.size.width * 0.2, r.size.height * 0.2);
	CGFloat w = MAX(1.2, r.size.width / 18);
	NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect: c];
	[[NSColor whiteColor] set];
	[p setLineWidth: w];
	[p stroke];
	p = [NSBezierPath bezierPathWithOvalInRect: NSInsetRect(c, c.size.width * 0.28, 0)];
	[p setLineWidth: w];
	[p stroke];
	p = [NSBezierPath bezierPath];
	[p setLineWidth: w];
	[p moveToPoint: NSMakePoint(NSMidX(c), NSMinY(c))];
	[p lineToPoint: NSMakePoint(NSMidX(c), NSMaxY(c))];
	[p moveToPoint: NSMakePoint(NSMinX(c), NSMidY(c))];
	[p lineToPoint: NSMakePoint(NSMaxX(c), NSMidY(c))];
	[p moveToPoint: NSMakePoint(NSMinX(c) + c.size.width * 0.1, NSMinY(c) + c.size.height * 0.75)];
	[p lineToPoint: NSMakePoint(NSMaxX(c) - c.size.width * 0.1, NSMinY(c) + c.size.height * 0.75)];
	[p moveToPoint: NSMakePoint(NSMinX(c) + c.size.width * 0.1, NSMinY(c) + c.size.height * 0.25)];
	[p lineToPoint: NSMakePoint(NSMaxX(c) - c.size.width * 0.1, NSMinY(c) + c.size.height * 0.25)];
	[p stroke];
}

static void
clockFace(NSRect r, NSColor *hands)
{
	NSRect c = NSInsetRect(r, r.size.width * 0.17, r.size.height * 0.17);
	NSPoint m = NSMakePoint(NSMidX(c), NSMidY(c));
	CGFloat rad = c.size.width / 2;
	NSBezierPath *p;
	int i;
	[[NSColor whiteColor] set];
	[[NSBezierPath bezierPathWithOvalInRect: c] fill];
	[[hands colorWithAlphaComponent: 0.55] set];
	for (i = 0; i < 12; i++) {
		CGFloat a = i * M_PI / 6, inner = rad * (i % 3 ? 0.84 : 0.74);
		p = [NSBezierPath bezierPath];
		[p setLineWidth: MAX(0.8, r.size.width / 40)];
		[p moveToPoint: NSMakePoint(m.x + cos(a) * inner, m.y + sin(a) * inner)];
		[p lineToPoint: NSMakePoint(m.x + cos(a) * rad * 0.92, m.y + sin(a) * rad * 0.92)];
		[p stroke];
	}
	[hands set];
	p = [NSBezierPath bezierPath];
	[p setLineWidth: MAX(1.4, r.size.width / 16)];
	[p setLineCapStyle: NSRoundLineCapStyle];
	[p moveToPoint: m];
	[p lineToPoint: NSMakePoint(m.x, m.y + rad * 0.62)];	/* 12 o'clock */
	[p moveToPoint: m];
	[p lineToPoint: NSMakePoint(m.x + rad * 0.45, m.y - rad * 0.12)];	/* about ten past */
	[p stroke];
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(m.x - rad * 0.09, m.y - rad * 0.09, rad * 0.18, rad * 0.18)] fill];
}

static void
picture(NSRect r)
{
	NSRect f = NSInsetRect(r, r.size.width * 0.17, r.size.height * 0.24);
	NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: f xRadius: r.size.width * 0.06 yRadius: r.size.width * 0.06];
	[[NSColor whiteColor] set];
	[p setLineWidth: MAX(1.2, r.size.width / 18)];
	[p stroke];
	/* mountains */
	p = [NSBezierPath bezierPath];
	[p moveToPoint: NSMakePoint(NSMinX(f) + 1, NSMinY(f) + 1)];
	[p lineToPoint: NSMakePoint(NSMinX(f) + f.size.width * 0.38, NSMinY(f) + f.size.height * 0.62)];
	[p lineToPoint: NSMakePoint(NSMinX(f) + f.size.width * 0.58, NSMinY(f) + f.size.height * 0.36)];
	[p lineToPoint: NSMakePoint(NSMinX(f) + f.size.width * 0.72, NSMinY(f) + f.size.height * 0.5)];
	[p lineToPoint: NSMakePoint(NSMaxX(f) - 1, NSMinY(f) + 1)];
	[p closePath];
	[p fill];
	/* sun */
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(NSMinX(f) + f.size.width * 0.66, NSMinY(f) + f.size.height * 0.62,
	                                                    f.size.width * 0.16, f.size.width * 0.16)] fill];
}

static void
person(NSPoint base, CGFloat s, NSColor *c)
{
	NSBezierPath *body = [NSBezierPath bezierPath];
	[c set];
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(base.x - s * 0.2, base.y + s * 0.52, s * 0.4, s * 0.4)] fill];
	[body appendBezierPathWithArcWithCenter: NSMakePoint(base.x, base.y) radius: s * 0.4 startAngle: 0 endAngle: 180];
	[body closePath];
	[body fill];
}

static void
people(NSRect r)
{
	CGFloat s = r.size.width;
	person(NSMakePoint(NSMidX(r) + s * 0.14, NSMinY(r) + s * 0.24), s * 0.52, [NSColor colorWithCalibratedWhite: 1 alpha: 0.7]);
	person(NSMakePoint(NSMidX(r) - s * 0.08, NSMinY(r) + s * 0.2), s * 0.6, [NSColor whiteColor]);
}

void
TurinDrawIcon(TurinIconKind kind, NSRect r)
{
	switch (kind) {
	case TurinIconWifi:
		tile(r, rgb(0.33, 0.66, 1.0), rgb(0.10, 0.42, 0.95));
		TurinDrawWifiFan(NSInsetRect(r, r.size.width * 0.18, r.size.height * 0.25), 3, NO, [NSColor whiteColor]);
		break;
	case TurinIconNetwork:
		tile(r, rgb(0.52, 0.55, 1.0), rgb(0.30, 0.30, 0.86));
		globe(r);
		break;
	case TurinIconDateTime:
		tile(r, rgb(1.0, 0.55, 0.35), rgb(0.93, 0.27, 0.25));
		clockFace(r, rgb(0.85, 0.25, 0.22));
		break;
	case TurinIconBackground:
		tile(r, rgb(0.25, 0.82, 0.90), rgb(0.55, 0.36, 0.93));
		picture(r);
		break;
	case TurinIconUsers:
		tile(r, rgb(0.55, 0.85, 0.45), rgb(0.18, 0.62, 0.36));
		people(r);
		break;
	}
}

void
TurinDrawAvatar(NSRect r, NSString *name)
{
	static CGFloat palette[][3] = { { 0.93, 0.36, 0.33 }, { 0.98, 0.62, 0.22 }, { 0.30, 0.70, 0.40 }, { 0.20, 0.55, 0.90 },
	                               { 0.55, 0.40, 0.88 }, { 0.90, 0.38, 0.65 }, { 0.20, 0.68, 0.72 }, { 0.50, 0.55, 0.60 } };
	NSUInteger h = 0, i, n = [name length];
	NSArray *words = [[name stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]
	                     componentsSeparatedByString: @" "];
	NSMutableString *ini = [NSMutableString string];
	NSDictionary *a;
	NSSize sz;
	CGFloat *c;
	for (i = 0; i < n; i++) h = h * 31 + [name characterAtIndex: i];
	c = palette[h % (sizeof palette / sizeof palette[0])];
	{
		NSGradient *g = [[[NSGradient alloc] initWithStartingColor: rgb(c[0] * 0.85, c[1] * 0.85, c[2] * 0.85)
		                                               endingColor: rgb(MIN(1, c[0] * 1.12), MIN(1, c[1] * 1.12), MIN(1, c[2] * 1.12))] autorelease];
		[g drawInBezierPath: [NSBezierPath bezierPathWithOvalInRect: r] angle: 90];
	}
	for (NSString *w in words) {
		if (![w length]) continue;
		[ini appendString: [[w substringToIndex: 1] uppercaseString]];
		if ([ini length] == 2) break;
	}
	if (![ini length]) [ini appendString: @"?"];
	a = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: floor(r.size.height * 0.4)], NSFontAttributeName,
	     [NSColor whiteColor], NSForegroundColorAttributeName, nil];
	sz = [ini sizeWithAttributes: a];
	[ini drawAtPoint: NSMakePoint(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2) withAttributes: a];
}

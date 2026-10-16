#import "TurinBackgroundPane.h"
#import "TurinImage.h"
#import "TurinUtil.h"

/* Milan's defaults (MilanWallpaper.m) */
static NSString *const kDomain = @"Milan", *kPath = @"MilanWallpaperPath", *kFill = @"MilanWallpaperFill",
                *kColor = @"MilanWallpaperColor", *kChanged = @"MilanWallpaperChanged";

static BOOL
isPicture(NSString *e)
{
	e = [e lowercaseString];
	return [e isEqualToString: @"png"] || [e isEqualToString: @"tif"] || [e isEqualToString: @"tiff"]
	    || [e isEqualToString: @"jpg"] || [e isEqualToString: @"jpeg"];
}

static NSColor *
defaultColor(void)
{
	return [NSColor colorWithCalibratedRed: 0.32 green: 0.31 blue: 0.43 alpha: 1];
}

/* Milan's bundle, for the wallpapers it ships (wp-*.png in its Resources) */
static NSBundle *
milanBundle(void)
{
	NSString *p = [[NSWorkspace sharedWorkspace] fullPathForApplication: @"Milan"];
	NSBundle *b = p ? [NSBundle bundleWithPath: p] : nil;
	if (!b) b = [NSBundle bundleWithPath: @"/Applications/Milan.app"];
	return b;
}

/* draws the picture into `canvas` (a rect of `size`) as Milan places it on the desktop (MilanWallpaper -canvasOfSize:) */
static void
placePicture(NSImage *pic, TurinFill fill, NSRect canvas)
{
	NSSize ps = [pic size], size = canvas.size;
	CGFloat sx, sy, s;
	NSRect dst;
	if (ps.width <= 0 || ps.height <= 0) return;
	if (fill == TurinFillTile) {
		/* tiles at the screen's scale: the preview shrinks the screen, so shrink the tile alike */
		CGFloat k = size.width / [[NSScreen mainScreen] frame].size.width, x, y, tw = ps.width * k, th = ps.height * k;
		if (tw < 2 || th < 2) return;
		for (y = 0; y < size.height; y += th)
			for (x = 0; x < size.width; x += tw)
				[pic drawInRect: NSMakeRect(canvas.origin.x + x, canvas.origin.y + y, tw, th) fromRect: NSZeroRect
				      operation: NSCompositeSourceOver fraction: 1.0];
		return;
	}
	sx = size.width / ps.width; sy = size.height / ps.height;
	switch (fill) {
	case TurinFillStretch: dst = NSMakeRect(0, 0, size.width, size.height); break;
	case TurinFillFit: s = MIN(sx, sy); dst = NSMakeRect((size.width - ps.width * s) / 2, (size.height - ps.height * s) / 2, ps.width * s, ps.height * s); break;
	case TurinFillCenter: {
		CGFloat k = size.width / [[NSScreen mainScreen] frame].size.width;
		dst = NSMakeRect((size.width - ps.width * k) / 2, (size.height - ps.height * k) / 2, ps.width * k, ps.height * k);
		break;
	}
	default: s = MAX(sx, sy); dst = NSMakeRect((size.width - ps.width * s) / 2, (size.height - ps.height * s) / 2, ps.width * s, ps.height * s); break;
	}
	dst.origin.x += canvas.origin.x;
	dst.origin.y += canvas.origin.y;
	[pic drawInRect: dst fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0];
}

/* ---- the preview: a small screen showing the background as it will look ---- */

@interface TurinBackgroundPreview : NSView {
	TurinBackgroundPane *pane;
	NSImage *cache;
	NSString *cachePath;
}
- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p;
@end

@implementation TurinBackgroundPreview

- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (void) dealloc { [cache release]; [cachePath release]; [super dealloc]; }
- (BOOL) isFlipped { return NO; }

- (void) drawRect: (NSRect)dirty
{
	NSRect b = [self bounds];
	NSSize scr = [[NSScreen mainScreen] frame].size;
	CGFloat k = MIN((b.size.width - 16) / scr.width, (b.size.height - 16) / scr.height);
	NSRect screen = NSMakeRect(floor(NSMidX(b) - scr.width * k / 2), floor(NSMidY(b) - scr.height * k / 2),
	                           floor(scr.width * k), floor(scr.height * k));
	NSString *p = [pane imagePath];
	NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(screen, -6, -6) xRadius: 8 yRadius: 8];
	[[NSColor colorWithCalibratedWhite: 0.15 alpha: 1] set];
	[bezel fill];
	[[[pane color] colorUsingColorSpaceName: NSCalibratedRGBColorSpace] set];
	NSRectFill(screen);
	if (![p isEqual: cachePath]) {
		[cache release];
		cache = [p length] ? [TurinLoadImage(p) retain] : nil;
		[cachePath release];
		cachePath = [p copy];
	}
	if (cache) {
		[NSGraphicsContext saveGraphicsState];
		NSRectClip(screen);
		placePicture(cache, [pane fill], screen);
		[NSGraphicsContext restoreGraphicsState];
	}
	/* the menu bar along the top, so it reads as a screen */
	[[NSColor colorWithCalibratedWhite: 1 alpha: 0.75] set];
	NSRectFillUsingOperation(NSMakeRect(NSMinX(screen), NSMaxY(screen) - 6, NSWidth(screen), 6), NSCompositeSourceOver);
}

@end

/* ---- the pictures (Milan's MilanThumbView) ---- */

#define THUMB_W 120.0
#define THUMB_H 76.0
#define THUMB_GAP 14.0

@interface TurinThumbView : NSView {
	TurinBackgroundPane *pane;
	NSArray *pictures;	/* nil entry (index 0) = no picture */
	NSMutableDictionary *thumbs;
}
- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p;
- (void) reload;
@end

@implementation TurinThumbView

- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p
{
	if (!(self = [super initWithFrame: f])) return nil;
	pane = p;
	thumbs = [[NSMutableDictionary alloc] init];
	[self registerForDraggedTypes: [NSArray arrayWithObject: NSFilenamesPboardType]];
	return self;
}

- (void) dealloc { [pictures release]; [thumbs release]; [super dealloc]; }
- (BOOL) isFlipped { return YES; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }

- (NSInteger) perRow { return MAX(1, (NSInteger)((NSWidth([self bounds]) - THUMB_GAP) / (THUMB_W + THUMB_GAP))); }

- (NSRect) rectForIndex: (NSInteger)i
{
	NSInteger per = [self perRow];
	CGFloat used = per * (THUMB_W + THUMB_GAP) - THUMB_GAP, left = floor((NSWidth([self bounds]) - used) / 2);
	return NSMakeRect(left + (i % per) * (THUMB_W + THUMB_GAP), THUMB_GAP + (i / per) * (THUMB_H + 26), THUMB_W, THUMB_H);
}

- (void) reload
{
	NSScrollView *sv = [self enclosingScrollView];
	CGFloat h;
	[pictures release];
	pictures = [[TurinBackgroundPane availablePictures] retain];
	h = THUMB_GAP + (([pictures count] + 1 + [self perRow] - 1) / [self perRow]) * (THUMB_H + 26);
	[self setFrameSize: NSMakeSize(NSWidth([self frame]), MAX(h, sv ? [sv contentSize].height : 0))];
	[self setNeedsDisplay: YES];
}

- (NSImage *) thumbFor: (NSString *)p
{
	NSImage *t = [thumbs objectForKey: p], *src;
	if (t) return t;
	src = TurinLoadImage(p);
	if (!src) return nil;
	t = [[[NSImage alloc] initWithSize: NSMakeSize(THUMB_W, THUMB_H)] autorelease];
	[t lockFocus];
	{	/* the view is flipped and an NSImage drawn into a flipped view comes out upside down on this back end (setFlipped:
		 * has no effect), so the thumbnail is made upside down on purpose -- as Milan does */
		NSAffineTransform *flip = [NSAffineTransform transform];
		[flip translateXBy: 0 yBy: THUMB_H];
		[flip scaleXBy: 1 yBy: -1];
		[flip concat];
	}
	placePicture(src, TurinFillFill, NSMakeRect(0, 0, THUMB_W, THUMB_H));
	[t unlockFocus];
	[thumbs setObject: t forKey: p];
	return t;
}

- (void) drawRect: (NSRect)dirty
{
	NSInteger i, n = [pictures count] + 1;
	NSString *cur = [pane imagePath];
	NSMutableParagraphStyle *ps = [[[NSMutableParagraphStyle alloc] init] autorelease];
	NSDictionary *a;
	[ps setAlignment: NSCenterTextAlignment];
	[ps setLineBreakMode: NSLineBreakByTruncatingTail];
	a = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 10], NSFontAttributeName,
	     [NSColor colorWithCalibratedWhite: 0.15 alpha: 1], NSForegroundColorAttributeName, ps, NSParagraphStyleAttributeName, nil];
	[[NSColor whiteColor] set];
	NSRectFill(dirty);
	for (i = 0; i < n; i++) {
		NSRect r = [self rectForIndex: i];
		NSString *p = i == 0 ? nil : [pictures objectAtIndex: i - 1];
		BOOL on = i == 0 ? ![cur length] : [p isEqualToString: cur];
		NSImage *t;
		NSString *name;
		if (!NSIntersectsRect(NSInsetRect(r, -6, -6 - 20), dirty)) continue;
		t = p ? [self thumbFor: p] : nil;
		if (on) {
			[TurinAccent() set];
			[[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, -4, -4) xRadius: 6 yRadius: 6] fill];
		}
		if (t) [t drawAtPoint: r.origin fromRect: NSZeroRect operation: NSCompositeCopy fraction: 1.0];
		else {
			[[pane color] set];
			NSRectFill(r);
		}
		[[NSColor colorWithCalibratedWhite: 0 alpha: 0.25] set];
		NSFrameRect(r);
		name = p ? [[[p lastPathComponent] stringByDeletingPathExtension] stringByReplacingOccurrencesOfString: @"wp-" withString: @""]
		         : @"Solid Colour";
		if ([p hasPrefix: [[milanBundle() resourcePath] stringByAppendingString: @"/"]]) name = [name capitalizedString];
		[name drawInRect: NSMakeRect(r.origin.x - 4, NSMaxY(r) + 5, r.size.width + 8, 14) withAttributes: a];
	}
}

- (void) mouseDown: (NSEvent *)ev
{
	NSPoint p = [self convertPoint: [ev locationInWindow] fromView: nil];
	NSInteger i, n = [pictures count] + 1;
	for (i = 0; i < n; i++)
		if (NSPointInRect(p, [self rectForIndex: i])) {
			[pane setImagePath: i == 0 ? nil : [pictures objectAtIndex: i - 1] fill: [pane fill] color: [pane color]];
			return;
		}
}

/* dropping picture files here copies them into ~/Pictures and lists them (as in Milan) */
- (NSDragOperation) draggingEntered: (id <NSDraggingInfo>)info { return NSDragOperationCopy; }

- (BOOL) performDragOperation: (id <NSDraggingInfo>)info
{
	NSArray *paths = [[info draggingPasteboard] propertyListForType: NSFilenamesPboardType];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *pics = [NSHomeDirectory() stringByAppendingPathComponent: @"Pictures"], *p, *last = nil;
	[fm createDirectoryAtPath: pics withIntermediateDirectories: YES attributes: nil error: NULL];
	for (p in paths)
		if (isPicture([p pathExtension])) {
			NSString *to = [pics stringByAppendingPathComponent: [p lastPathComponent]];
			if ([p isEqual: to] || [fm copyItemAtPath: p toPath: to error: NULL]) last = to;
		}
	[self reload];
	if (last) [pane setImagePath: last fill: [pane fill] color: [pane color]];
	return YES;
}

@end

/* ---- the colour swatches (Milan's MilanSwatchView) ---- */

static NSArray *
swatchColors(void)
{
	return [NSArray arrayWithObjects:
	    [NSColor colorWithCalibratedRed: 0.32 green: 0.31 blue: 0.43 alpha: 1], [NSColor colorWithCalibratedWhite: 0.20 alpha: 1],
	    [NSColor colorWithCalibratedWhite: 0.55 alpha: 1], [NSColor colorWithCalibratedRed: 0.13 green: 0.38 blue: 0.75 alpha: 1],
	    [NSColor colorWithCalibratedRed: 0.12 green: 0.53 blue: 0.42 alpha: 1], [NSColor colorWithCalibratedRed: 0.75 green: 0.28 blue: 0.30 alpha: 1],
	    [NSColor colorWithCalibratedRed: 0.90 green: 0.62 blue: 0.20 alpha: 1], [NSColor colorWithCalibratedRed: 0.45 green: 0.30 blue: 0.65 alpha: 1],
	    nil];
}

static BOOL
sameColor(NSColor *a, NSColor *b)
{
	a = [a colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
	b = [b colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
	return a && b && fabs([a redComponent] - [b redComponent]) < 0.01 && fabs([a greenComponent] - [b greenComponent]) < 0.01
	    && fabs([a blueComponent] - [b blueComponent]) < 0.01;
}

@interface TurinSwatchView : NSView { TurinBackgroundPane *pane; }
- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p;
@end

@implementation TurinSwatchView
- (id) initWithFrame: (NSRect)f pane: (TurinBackgroundPane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (NSRect) rectAt: (NSUInteger)i { return NSMakeRect(4 + i * 32, 4, 24, 24); }
- (void) drawRect: (NSRect)dirty
{
	NSUInteger i;
	NSArray *s = swatchColors();
	for (i = 0; i < [s count]; i++) {
		NSRect r = [self rectAt: i];
		if (sameColor([s objectAtIndex: i], [pane color])) {
			[TurinAccent() set];
			[[NSBezierPath bezierPathWithOvalInRect: NSInsetRect(r, -3, -3)] fill];
			[[NSColor whiteColor] set];
			[[NSBezierPath bezierPathWithOvalInRect: NSInsetRect(r, -1, -1)] fill];
		}
		[(NSColor *)[s objectAtIndex: i] set];
		[[NSBezierPath bezierPathWithOvalInRect: r] fill];
		[[NSColor colorWithCalibratedWhite: 0 alpha: 0.2] set];
		[[NSBezierPath bezierPathWithOvalInRect: NSInsetRect(r, 0.5, 0.5)] stroke];
	}
}
- (void) mouseDown: (NSEvent *)ev
{
	NSPoint p = [self convertPoint: [ev locationInWindow] fromView: nil];
	NSArray *s = swatchColors();
	NSUInteger i;
	for (i = 0; i < [s count]; i++)
		if (NSPointInRect(p, NSInsetRect([self rectAt: i], -3, -3))) {
			[pane setImagePath: [pane imagePath] fill: [pane fill] color: [s objectAtIndex: i]];
			return;
		}
}
@end

/* ---- the pane ---- */

@implementation TurinBackgroundPane

- (NSString *) title { return @"Background"; }
- (TurinIconKind) icon { return TurinIconBackground; }
- (NSString *) imagePath { return imagePath; }
- (NSColor *) color { return color; }
- (TurinFill) fill { return fill; }

+ (NSArray *) availablePictures
{
	NSMutableArray *out = [NSMutableArray array];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = [milanBundle() resourcePath], *n, *pics;
	for (n in [[fm contentsOfDirectoryAtPath: dir error: NULL] sortedArrayUsingSelector: @selector(compare:)])
		if ([n hasPrefix: @"wp-"] && [n hasSuffix: @".png"]) [out addObject: [dir stringByAppendingPathComponent: n]];
	pics = [NSHomeDirectory() stringByAppendingPathComponent: @"Pictures"];
	for (n in [[fm contentsOfDirectoryAtPath: pics error: NULL] sortedArrayUsingSelector: @selector(compare:)])
		if (isPicture([n pathExtension])) [out addObject: [pics stringByAppendingPathComponent: n]];
	return out;
}

/* Milan's settings as it reads them (MilanWallpaper -init): no path and no colour saved yet is the first run's picture */
- (void) load
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSDictionary *m;
	NSArray *c;
	NSString *p;
	[d synchronize];	/* re-reads Milan's file when Milan changed it */
	m = [d persistentDomainForName: kDomain];
	c = [m objectForKey: kColor];
	p = [m objectForKey: kPath];
	[color release];
	if ([c isKindOfClass: [NSArray class]] && [c count] == 3)
		color = [[NSColor colorWithCalibratedRed: [[c objectAtIndex: 0] floatValue] green: [[c objectAtIndex: 1] floatValue]
		                                    blue: [[c objectAtIndex: 2] floatValue] alpha: 1] retain];
	else
		color = [defaultColor() retain];
	fill = [m objectForKey: kFill] ? (TurinFill)[[m objectForKey: kFill] intValue] : TurinFillFill;
	[imagePath release];
	imagePath = nil;
	if ([p isKindOfClass: [NSString class]]) imagePath = [p length] ? [p copy] : nil;
	else if (!c) {
		NSString *dp = [milanBundle() pathForResource: @"wp-aurora" ofType: @"png"];
		if (dp) imagePath = [dp copy];
	}
}

- (void) refresh
{
	[placement setSelectedSegment: (NSInteger)fill];
	[preview setNeedsDisplay: YES];
	[thumbs setNeedsDisplay: YES];
	[swatches setNeedsDisplay: YES];
}

- (void) milanChanged: (NSNotification *)n
{
	if ([[n object] isEqual: @"Turin"]) return;	/* our own */
	[self load];
	[self refresh];
}

- (id) init
{
	if ((self = [super init])) {
		[self load];
		/* gnustep-base raises when it cannot reach or start gdnc; Turin then just does not follow Milan's own changes */
		@try {
			[[NSDistributedNotificationCenter defaultCenter] addObserver: self selector: @selector(milanChanged:)
			                                                        name: kChanged object: nil];
		} @catch (NSException *e) {
			NSLog(@"Turin: no distributed notifications (%@)", [e reason]);
		}
	}
	return self;
}

- (void) dealloc
{
	@try { [[NSDistributedNotificationCenter defaultCenter] removeObserver: self]; } @catch (NSException *e) {}
	[imagePath release]; [color release]; [preview release]; [thumbs release]; [swatches release]; [scroll release];
	[placement release]; [note release];
	[super dealloc];
}

- (void) setImagePath: (NSString *)p fill: (TurinFill)f color: (NSColor *)c
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSColor *rgb = [c colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
	NSMutableDictionary *m;
	[d synchronize];
	m = [[[d persistentDomainForName: kDomain] mutableCopy] autorelease];
	if (!m) m = [NSMutableDictionary dictionary];
	{	/* p and c are often the current values: take the new ones before letting go of the old */
		NSString *op = imagePath;
		NSColor *oc = color;
		imagePath = [p length] ? [p copy] : nil;
		color = [c retain];
		[op release];
		[oc release];
	}
	fill = f;
	[m setObject: imagePath ? imagePath : @"" forKey: kPath];
	[m setObject: [NSNumber numberWithInt: f] forKey: kFill];
	if (rgb)
		[m setObject: [NSArray arrayWithObjects: [NSNumber numberWithFloat: [rgb redComponent]],
		               [NSNumber numberWithFloat: [rgb greenComponent]], [NSNumber numberWithFloat: [rgb blueComponent]], nil]
		      forKey: kColor];
	[d setPersistentDomain: m forName: kDomain];
	[d synchronize];
	@try {
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName: kChanged object: @"Turin" userInfo: nil
		                                                   deliverImmediately: YES];
		[note setStringValue: @"Drop PNG, TIFF or JPEG pictures on the list to add them (they are copied to ~/Pictures)."];
	} @catch (NSException *e) {
		[note setStringValue: @"Saved, but Milan could not be told (no gdnc): it shows the change when it next starts."];
	}
	[self refresh];
}

- (void) placementChanged: (NSSegmentedControl *)sc
{
	[self setImagePath: imagePath fill: (TurinFill)[sc selectedSegment] color: color];
}

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth;
	NSArray *modes = [NSArray arrayWithObjects: @"Fill", @"Fit", @"Stretch", @"Center", @"Tile", nil];
	NSUInteger i;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 330, W - 40, 170)],
	    [NSValue valueWithRect: NSMakeRect(20, 16, W - 40, 304)], nil]];
	preview = [[TurinBackgroundPreview alloc] initWithFrame: NSMakeRect(30, 338, 250, 154) pane: self];
	[v addSubview: preview];

	[v addSubview: TurinLabel(NSMakeRect(300, 460, 200, 18), @"Placement", 12, YES)];
	placement = [[NSSegmentedControl alloc] initWithFrame: NSMakeRect(300, 430, 250, 24)];
	[placement setSegmentCount: [modes count]];
	for (i = 0; i < [modes count]; i++) { [placement setLabel: [modes objectAtIndex: i] forSegment: i]; [placement setWidth: 48 forSegment: i]; }
	[placement setTarget: self];
	[placement setAction: @selector(placementChanged:)];
	[v addSubview: placement];

	[v addSubview: TurinLabel(NSMakeRect(300, 398, 200, 18), @"Colour", 12, YES)];
	swatches = [[TurinSwatchView alloc] initWithFrame: NSMakeRect(296, 362, 270, 32) pane: self];
	[v addSubview: swatches];

	scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(30, 46, W - 60, 264)];
	[scroll setHasVerticalScroller: YES];
	[scroll setBorderType: NSBezelBorder];
	thumbs = [[TurinThumbView alloc] initWithFrame: NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height) pane: self];
	[scroll setDocumentView: thumbs];
	[v addSubview: scroll];
	note = [TurinLabel(NSMakeRect(30, 22, W - 60, 16), milanBundle()
	    ? @"Drop PNG, TIFF or JPEG pictures on the list to add them (they are copied to ~/Pictures)."
	    : @"Milan is not installed: the desktop background is Milan's, so changes show once it is.", 10, NO) retain];
	[note setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.5]];
	[v addSubview: note];
	[(TurinThumbView *)thumbs reload];
	[self refresh];
}

- (void) didShow
{
	[self load];
	[(TurinThumbView *)thumbs reload];	/* ~/Pictures may have changed */
	[self refresh];
}

@end

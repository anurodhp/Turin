#import "TurinWindow.h"
#import "TurinUtil.h"

#define SidebarW 210.0
#define RowH 36.0
#define TopPad 16.0

@interface TurinSidebar : NSView {
	TurinWindow *owner;
}
- (id) initWithFrame: (NSRect)f owner: (TurinWindow *)o;
@end

@implementation TurinSidebar

- (id) initWithFrame: (NSRect)f owner: (TurinWindow *)o
{
	if ((self = [super initWithFrame: f])) owner = o;
	return self;
}

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (BOOL) acceptsFirstResponder { return YES; }

- (NSRect) rowRect: (NSUInteger)i
{
	return NSMakeRect(10, NSHeight([self bounds]) - TopPad - (i + 1) * RowH, SidebarW - 20, RowH - 4);
}

- (void) drawRect: (NSRect)dirty
{
	NSArray *panes = [owner panes];
	NSUInteger i;
	[[NSColor colorWithCalibratedWhite: 0.90 alpha: 1] set];
	NSRectFill(dirty);
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.12] set];
	NSRectFill(NSMakeRect(NSWidth([self bounds]) - 1, 0, 1, NSHeight([self bounds])));
	for (i = 0; i < [panes count]; i++) {
		TurinPane *p = [panes objectAtIndex: i];
		NSRect r = [self rowRect: i];
		BOOL sel = (NSInteger)i == [owner currentIndex];
		NSDictionary *a = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
		                   sel ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0.1 alpha: 1],
		                   NSForegroundColorAttributeName, nil];
		if (sel) {
			[TurinAccent() set];
			[[NSBezierPath bezierPathWithRoundedRect: r xRadius: 6 yRadius: 6] fill];
		}
		TurinDrawIcon([p icon], NSMakeRect(NSMinX(r) + 6, NSMidY(r) - 12, 24, 24));
		[[p title] drawAtPoint: NSMakePoint(NSMinX(r) + 40, NSMidY(r) - 8) withAttributes: a];
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint pt = [self convertPoint: [e locationInWindow] fromView: nil];
	NSUInteger i;
	for (i = 0; i < [[owner panes] count]; i++)
		if (NSPointInRect(pt, [self rowRect: i])) { [owner showPaneAtIndex: i]; return; }
}

/* up/down arrows move through the panes */
- (void) keyDown: (NSEvent *)e
{
	NSString *k = [e charactersIgnoringModifiers];
	unichar c = [k length] ? [k characterAtIndex: 0] : 0;
	NSInteger n = [[owner panes] count], cur = [owner currentIndex];
	if (c == NSUpArrowFunctionKey && cur > 0) [owner showPaneAtIndex: cur - 1];
	else if (c == NSDownArrowFunctionKey && cur < n - 1) [owner showPaneAtIndex: cur + 1];
	else [super keyDown: e];
}

@end

@implementation TurinWindow

- (id) initWithPanes: (NSArray *)p
{
	NSRect scr = [[NSScreen mainScreen] visibleFrame];
	CGFloat w = SidebarW + TurinPaneWidth, h = TurinPaneHeight;
	if (!(self = [super init])) return nil;
	panes = [p retain];
	current = -1;
	window = [[NSWindow alloc] initWithContentRect: NSMakeRect(floor(NSMidX(scr) - w / 2), floor(NSMidY(scr) - h / 2), w, h)
	                                     styleMask: NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
	                                       backing: NSBackingStoreBuffered defer: NO];
	[window setTitle: @"Settings"];
	[window setReleasedWhenClosed: NO];
	[window setFrameAutosaveName: @"TurinMain"];
	sidebar = [[TurinSidebar alloc] initWithFrame: NSMakeRect(0, 0, SidebarW, h) owner: self];
	holder = [[NSView alloc] initWithFrame: NSMakeRect(SidebarW, 0, TurinPaneWidth, h)];
	[[window contentView] addSubview: sidebar];
	[[window contentView] addSubview: holder];
	return self;
}

- (void) dealloc { [window release]; [panes release]; [sidebar release]; [holder release]; [super dealloc]; }
- (NSWindow *) window { return window; }
- (NSArray *) panes { return panes; }
- (NSInteger) currentIndex { return current; }

- (void) showPaneAtIndex: (NSInteger)i
{
	TurinPane *p;
	if (i < 0 || i >= (NSInteger)[panes count] || i == current) return;
	[TurinDialog close];	/* a dialog belongs to the pane it was opened from */
	if (current >= 0) {
		p = [panes objectAtIndex: current];
		[[p view] removeFromSuperview];
		[p didHide];
	}
	current = i;
	p = [panes objectAtIndex: i];
	[[p view] setFrameOrigin: NSZeroPoint];
	[holder addSubview: [p view]];
	[window setTitle: [p title]];
	[[NSUserDefaults standardUserDefaults] setObject: [p title] forKey: @"TurinLastPane"];
	[sidebar setNeedsDisplay: YES];
	[p didShow];
	[window makeFirstResponder: sidebar];
	[window display];
}

- (NSInteger) indexOfPaneNamed: (NSString *)name
{
	NSUInteger i;
	for (i = 0; name && i < [panes count]; i++)
		if ([[[panes objectAtIndex: i] title] caseInsensitiveCompare: name] == NSOrderedSame) return i;
	return -1;
}

@end

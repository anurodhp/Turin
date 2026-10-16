#import "TurinWifiPane.h"
#import "TurinUtil.h"
#include <ctype.h>

enum { ListRowH = 30 };

/* ---- the connected network ---- */

@interface TurinWifiCurrentView : NSView { TurinWifi *wifi; }
- (id) initWithFrame: (NSRect)f wifi: (TurinWifi *)w;
@end

@implementation TurinWifiCurrentView

- (id) initWithFrame: (NSRect)f wifi: (TurinWifi *)w { if ((self = [super initWithFrame: f])) wifi = w; return self; }
- (BOOL) isFlipped { return NO; }

- (void) drawRect: (NSRect)dirty
{
	NSRect b = [self bounds];
	NSDictionary *name = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 14], NSFontAttributeName,
	                      [NSColor blackColor], NSForegroundColorAttributeName, nil];
	NSDictionary *sub = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                     [NSColor colorWithCalibratedWhite: 0 alpha: 0.5], NSForegroundColorAttributeName, nil];
	NSDictionary *val = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                     [NSColor colorWithCalibratedWhite: 0.08 alpha: 1], NSForegroundColorAttributeName, nil];
	NSRect circle = NSMakeRect(4, NSMaxY(b) - 36, 32, 32);
	NSArray *d = [wifi details];
	NSUInteger i;
	if (![wifi associated] || ![wifi ssid]) {
		NSString *s = ![wifi known] ? @"Wi-Fi hardware was not found." : ![wifi enabled] ? @"Wi-Fi is turned off."
		            : [wifi joining] ? [NSString stringWithFormat: @"Joining “%@”…", [wifi joining]] : @"Not connected to a network.";
		[[NSColor colorWithCalibratedWhite: 0 alpha: 0.08] set];
		[[NSBezierPath bezierPathWithOvalInRect: circle] fill];
		TurinDrawWifiFan(NSMakeRect(NSMidX(circle) - 10, NSMinY(circle) + 7, 20, 16), 0, ![wifi enabled],
		                 [NSColor colorWithCalibratedWhite: 0.1 alpha: 1]);
		[s drawAtPoint: NSMakePoint(46, NSMidY(circle) - 8) withAttributes: name];
		if ([wifi remembered])
			[[NSString stringWithFormat: @"Remembered network: %@", [wifi remembered]] drawAtPoint: NSMakePoint(46, NSMidY(circle) - 30)
			                                                                         withAttributes: sub];
		return;
	}
	[TurinAccent() set];
	[[NSBezierPath bezierPathWithOvalInRect: circle] fill];
	TurinDrawWifiFan(NSMakeRect(NSMidX(circle) - 10, NSMinY(circle) + 7, 20, 16), TurinWifiBars([wifi rssi]), NO, [NSColor whiteColor]);
	[[wifi ssid] drawAtPoint: NSMakePoint(46, NSMidY(circle) - 1) withAttributes: name];
	[([wifi securedNow] ? @"Connected · Secured with WPA2" : @"Connected · Open network")
	    drawAtPoint: NSMakePoint(46, NSMidY(circle) - 16) withAttributes: sub];
	/* the details in two columns, macOS's Option-click list */
	for (i = 0; i < [d count]; i++) {
		NSArray *pair = [d objectAtIndex: i];
		CGFloat col = i < 5 ? 0 : 1, row = i < 5 ? i : i - 5;
		CGFloat x = 46 + col * 250, y = NSMaxY(b) - 64 - row * 19;
		NSString *label = [[pair objectAtIndex: 0] stringByAppendingString: @":"];
		[label drawAtPoint: NSMakePoint(x, y) withAttributes: sub];
		[[pair objectAtIndex: 1] drawAtPoint: NSMakePoint(x + 96, y) withAttributes: val];
	}
}

@end

/* ---- the networks in range ---- */

@interface TurinNetworkList : NSView {
	TurinWifi *wifi;
	TurinWifiPane *pane;
@public
	NSInteger selected;
}
- (id) initWithFrame: (NSRect)f wifi: (TurinWifi *)w pane: (TurinWifiPane *)p;
- (NSDictionary *) selectedNetwork;
- (void) reload;
@end

@interface TurinWifiPane (List)
- (void) joinSelected: (id)sender;
- (void) update;
@end

@implementation TurinNetworkList

- (id) initWithFrame: (NSRect)f wifi: (TurinWifi *)w pane: (TurinWifiPane *)p
{
	if ((self = [super initWithFrame: f])) { wifi = w; pane = p; selected = -1; }
	return self;
}

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }

- (NSArray *) shown { return [wifi enabled] ? [wifi networks] : nil; }

- (void) reload
{
	NSScrollView *sv = [self enclosingScrollView];
	CGFloat h = MAX([sv contentSize].height, [[self shown] count] * ListRowH);
	if (selected >= (NSInteger)[[self shown] count]) selected = -1;
	if (h != NSHeight([self frame])) [self setFrameSize: NSMakeSize(NSWidth([self frame]), h)];
	[self setNeedsDisplay: YES];
}

- (NSRect) rowRect: (NSUInteger)i { return NSMakeRect(0, NSHeight([self bounds]) - (i + 1) * ListRowH, NSWidth([self bounds]), ListRowH); }

- (NSDictionary *) selectedNetwork
{
	NSArray *n = [self shown];
	return selected >= 0 && selected < (NSInteger)[n count] ? [n objectAtIndex: selected] : nil;
}

- (void) drawRect: (NSRect)dirty
{
	NSArray *nets = [self shown];
	NSUInteger i;
	NSDictionary *ta = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0.08 alpha: 1], NSForegroundColorAttributeName, nil];
	NSDictionary *sa = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
	                    [NSColor whiteColor], NSForegroundColorAttributeName, nil];
	NSDictionary *ga = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0 alpha: 0.5], NSForegroundColorAttributeName, nil];
	[[NSColor whiteColor] set];
	NSRectFill(dirty);
	if (![nets count]) {
		NSString *s = ![wifi enabled] ? @"Turn Wi-Fi on to see the networks in range."
		            : [wifi scanning] ? @"Searching for networks…" : @"No networks found.";
		[s drawAtPoint: NSMakePoint(12, NSHeight([self bounds]) - 22) withAttributes: ga];
		return;
	}
	for (i = 0; i < [nets count]; i++) {
		NSDictionary *n = [nets objectAtIndex: i];
		NSRect r = [self rowRect: i];
		BOOL sel = (NSInteger)i == selected;
		NSString *right = [[wifi joining] isEqual: [n objectForKey: @"ssid"]] ? @"Connecting…" : nil;
		if (!NSIntersectsRect(r, dirty)) continue;
		if (sel) {
			[TurinAccent() set];
			NSRectFill(r);
		} else if (i % 2) {
			[[NSColor colorWithCalibratedWhite: 0.965 alpha: 1] set];
			NSRectFill(r);
		}
		TurinDrawWifiFan(NSMakeRect(12, NSMidY(r) - 6, 16, 12), TurinWifiBars([[n objectForKey: @"rssi"] intValue]), NO,
		                 sel ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0.1 alpha: 1]);
		[[n objectForKey: @"ssid"] drawAtPoint: NSMakePoint(40, NSMidY(r) - 8) withAttributes: sel ? sa : ta];
		if (right) {
			NSSize sz = [right sizeWithAttributes: ga];
			[right drawAtPoint: NSMakePoint(NSWidth(r) - 14 - sz.width, NSMidY(r) - 7) withAttributes: ga];
		} else {
			NSString *ch = [NSString stringWithFormat: @"%d dBm · ch %d", [[n objectForKey: @"rssi"] intValue],
			                [[n objectForKey: @"channel"] intValue]];
			NSSize sz = [ch sizeWithAttributes: ga];
			[ch drawAtPoint: NSMakePoint(NSWidth(r) - 34 - sz.width, NSMidY(r) - 7)
			 withAttributes: sel ? [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
			                       [NSColor colorWithCalibratedWhite: 1 alpha: 0.8], NSForegroundColorAttributeName, nil] : ga];
			if ([[n objectForKey: @"secure"] boolValue])
				TurinDrawLock(NSMakePoint(NSWidth(r) - 24, NSMidY(r) - 5),
				              sel ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0 alpha: 0.5]);
		}
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
	NSUInteger i, n = [[self shown] count];
	for (i = 0; i < n; i++)
		if (NSPointInRect(p, [self rowRect: i])) {
			selected = i;
			[self setNeedsDisplay: YES];
			[pane update];
			if ([e clickCount] == 2) [pane joinSelected: nil];
			return;
		}
}

@end

/* ---- the pane ---- */

@implementation TurinWifiPane

- (NSString *) title { return @"Wi-Fi"; }
- (TurinIconKind) icon { return TurinIconWifi; }

- (id) init
{
	if ((self = [super init]))
		wifi = [[TurinWifi alloc] initWithChangeHandler: ^{ [self update]; }];
	return self;
}

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth;
	NSView *icon;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 440, W - 40, 60)],
	    [NSValue valueWithRect: NSMakeRect(20, 250, W - 40, 176)],
	    [NSValue valueWithRect: NSMakeRect(20, 16, W - 40, 220)], nil]];
	/* header: the icon, the name, a status line and the switch */
	icon = [[[NSImageView alloc] initWithFrame: NSMakeRect(34, 452, 36, 36)] autorelease];
	{
		NSImage *img = [[[NSImage alloc] initWithSize: NSMakeSize(36, 36)] autorelease];
		[img lockFocus];
		TurinDrawIcon(TurinIconWifi, NSMakeRect(0, 0, 36, 36));
		[img unlockFocus];
		[(NSImageView *)icon setImage: img];
	}
	[v addSubview: icon];
	[v addSubview: TurinLabel(NSMakeRect(80, 470, 200, 20), @"Wi-Fi", 14, YES)];
	status = [TurinLabel(NSMakeRect(80, 450, 400, 18), @"", 11, NO) retain];
	[v addSubview: status];
	power = [[TurinSwitch alloc] initWithFrame: NSMakeRect(W - 80, 458, 40, 24)];
	[power setTarget: self];
	[power setAction: @selector(togglePower:)];
	[v addSubview: power];

	/* the network in use */
	current = [[TurinWifiCurrentView alloc] initWithFrame: NSMakeRect(34, 296, W - 68, 122) wifi: wifi];
	[v addSubview: current];
	forgetButton = [TurinButton(NSMakeRect(W - 214, 260, 180, 26), @"Forget This Network…", self, @selector(forget:)) retain];
	disconnectButton = [TurinButton(NSMakeRect(W - 324, 260, 104, 26), @"Disconnect", self, @selector(disconnect:)) retain];
	[v addSubview: forgetButton];
	[v addSubview: disconnectButton];

	/* the networks in range */
	[v addSubview: TurinLabel(NSMakeRect(34, 206, 200, 18), @"Other Networks", 12, YES)];
	scanLabel = [TurinLabel(NSMakeRect(160, 206, 200, 18), @"", 11, NO) retain];
	[scanLabel setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.5]];
	[v addSubview: scanLabel];
	scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(34, 62, W - 68, 140)];
	[scroll setHasVerticalScroller: YES];
	[scroll setBorderType: NSBezelBorder];
	list = [[TurinNetworkList alloc] initWithFrame: NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)
	                                          wifi: wifi pane: self];
	[scroll setDocumentView: list];
	[v addSubview: scroll];
	otherButton = [TurinButton(NSMakeRect(34, 26, 150, 26), @"Other Network…", self, @selector(joinOther:)) retain];
	scanButton = [TurinButton(NSMakeRect(W - 234, 26, 90, 26), @"Scan", self, @selector(rescan:)) retain];
	joinButton = [TurinButton(NSMakeRect(W - 134, 26, 100, 26), @"Join", self, @selector(joinSelected:)) retain];
	[v addSubview: otherButton];
	[v addSubview: scanButton];
	[v addSubview: joinButton];
	[self update];
}

- (void) dealloc
{
	[wifi release]; [power release]; [status release]; [current release]; [list release]; [scroll release];
	[disconnectButton release]; [forgetButton release]; [joinButton release]; [scanButton release]; [otherButton release];
	[scanLabel release];
	[super dealloc];
}

- (void) didShow { [wifi setActive: YES]; }
- (void) didHide { [wifi setActive: NO]; }

- (void) update
{
	NSString *s;
	BOOL root = TurinIsRoot(), on = [wifi enabled], busy = [wifi joining] != nil;
	if (!status) return;	/* not loaded yet */
	if (![wifi available]) s = @"This system has no IOKit library (/usr/lib/libiokituser.dylib).";
	else if (![wifi known]) s = @"No Wi-Fi hardware answered (boot with wifi=1).";
	else if ([wifi message]) s = [wifi message];
	else if (!on) s = @"Off";
	else if ([wifi joining]) s = [NSString stringWithFormat: @"Joining “%@”…", [wifi joining]];
	else if ([wifi associated]) s = [NSString stringWithFormat: @"Connected to “%@”", [wifi ssid]];
	else s = @"On, not connected";
	if (!root && [wifi known]) s = [s stringByAppendingString: @" — changing Wi-Fi needs the root account."];
	[status setStringValue: s];
	[status setTextColor: [wifi message] ? [NSColor colorWithCalibratedRed: 0.8 green: 0.15 blue: 0.12 alpha: 1]
	                                    : [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
	[power setOn: on];
	[power setEnabled: [wifi known] && root];
	[disconnectButton setEnabled: root && [wifi associated] && !busy];
	[forgetButton setEnabled: root && [wifi associated] && [[wifi remembered] isEqual: [wifi ssid]] && !busy];
	[joinButton setEnabled: root && on && !busy && [(TurinNetworkList *)list selectedNetwork] != nil];
	[otherButton setEnabled: root && on && !busy];
	[scanButton setEnabled: on && ![wifi scanning]];
	[scanLabel setStringValue: [wifi scanning] ? @"Searching…" : @""];
	[(TurinNetworkList *)list reload];
	[current setNeedsDisplay: YES];
}

- (void) togglePower: (id)sender { [wifi setEnabled: [power isOn]]; }
- (void) rescan: (id)sender { [wifi scan]; }
- (void) disconnect: (id)sender { [wifi disconnect]; }

- (void) forget: (id)sender
{
	NSString *name = [wifi ssid];
	if (!name) return;
	[TurinDialog showIn: [view window] title: [NSString stringWithFormat: @"Forget “%@”?", name]
	            message: @"The Pi will leave this network and no longer join it automatically. You will need its password to join it again."
	             fields: nil checkbox: nil checked: NO okTitle: @"Forget"
	         completion: ^BOOL(BOOL ok, NSArray *values, BOOL checked) {
		if (ok) [wifi forgetCurrent];
		return YES;
	}];
}

static BOOL
validPassphrase(NSString *psk)
{
	NSUInteger len = [psk lengthOfBytesUsingEncoding: NSUTF8StringEncoding], i;
	BOOL hex = len == 64;
	for (i = 0; hex && i < len; i++) hex = isxdigit([psk characterAtIndex: i]) != 0;
	return len >= 8 && (len < 64 || hex);
}

- (void) askPasswordFor: (NSString *)name
{
	[TurinDialog showIn: [view window] title: @"Join Wi-Fi Network"
	            message: [NSString stringWithFormat: @"The Wi-Fi network “%@” needs a password.", name]
	             fields: [NSArray arrayWithObject: TurinDialogField(@"Password:", @"", YES)]
	           checkbox: nil checked: NO okTitle: @"Join"
	         completion: ^BOOL(BOOL ok, NSArray *values, BOOL checked) {
		NSString *psk = [values objectAtIndex: 0];
		if (!ok) return YES;
		if (!validPassphrase(psk)) {
			[TurinDialog showError: @"A Wi-Fi password has 8 to 63 characters, or 64 hex digits."];
			return NO;
		}
		[wifi join: name password: psk];
		return YES;
	}];
}

- (void) joinSelected: (id)sender
{
	NSDictionary *n = [(TurinNetworkList *)list selectedNetwork];
	NSString *name = [n objectForKey: @"ssid"];
	if (!n || !TurinIsRoot() || [wifi joining]) return;
	if (![[n objectForKey: @"secure"] boolValue]) [wifi join: name password: @""];
	else if ([wifi hasSavedPasswordFor: name]) [wifi joinSaved: name];
	else [self askPasswordFor: name];
}

/* a hidden network, or one not in the list yet: its name, and a password if it has one */
- (void) joinOther: (id)sender
{
	[TurinDialog showIn: [view window] title: @"Join Other Network"
	            message: @"Enter the name of the network, and its password if it is secured. Leave the password empty for an open network."
	             fields: [NSArray arrayWithObjects: TurinDialogField(@"Network Name:", @"", NO), TurinDialogField(@"Password:", @"", YES), nil]
	           checkbox: nil checked: NO okTitle: @"Join"
	         completion: ^BOOL(BOOL ok, NSArray *values, BOOL checked) {
		NSString *name = [values objectAtIndex: 0], *psk = [values objectAtIndex: 1];
		if (!ok) return YES;
		if (![name length] || [name lengthOfBytesUsingEncoding: NSUTF8StringEncoding] > 32) {
			[TurinDialog showError: @"A network name has 1 to 32 characters."];
			return NO;
		}
		if ([psk length] && !validPassphrase(psk)) {
			[TurinDialog showError: @"A Wi-Fi password has 8 to 63 characters, or 64 hex digits."];
			return NO;
		}
		[wifi join: name password: psk];
		return YES;
	}];
}

@end

/* Turin: System Preferences for GNUstep + Window Maker on Darwin/XNU. See README.md.
 * Defaults (all optional): TurinPane (the pane to open: Wi-Fi, Network, Date & Time, Background, Users; `-TurinPane Users`
 * on the command line), TurinLastPane (the one shown when Turin last ran, kept by the window). */
#import <AppKit/AppKit.h>
#import "TurinWindow.h"
#import "TurinWifiPane.h"
#import "TurinNetworkPane.h"
#import "TurinDateTimePane.h"
#import "TurinBackgroundPane.h"
#import "TurinUsersPane.h"

@interface TurinApp : NSObject {
	TurinWindow *window;
}
@end

static NSMenuItem *
add_item(NSMenu *m, NSString *title, SEL action, NSString *key, id target)
{
	NSMenuItem *i = (NSMenuItem *)[m addItemWithTitle: title action: action keyEquivalent: key ? key : @""];
	[i setTarget: target];
	return i;
}

@implementation TurinApp

- (void) showAbout: (id)sender
{
	/* the keys GNUstep's info panel reads (GSInfoPanel.m), as Milan and Rome pass them */
	NSDictionary *opts = [NSDictionary dictionaryWithObjectsAndKeys:
	    @"Turin", @"ApplicationName",
	    @"System Preferences for GNUstep.", @"ApplicationDescription",
	    @"0.1", @"ApplicationRelease",
	    [NSArray arrayWithObject: @"Anurodh Pokharel"], @"Authors",
	    @"Copyright © 2026 Anurodh Pokharel. MIT license.", @"Copyright",
	    nil];
	[NSApp orderFrontStandardAboutPanelWithOptions: opts];
}

- (void) showPane: (NSMenuItem *)sender
{
	[[window window] makeKeyAndOrderFront: nil];
	[window showPaneAtIndex: [sender tag]];
}

- (void) buildMenus
{
	NSMenu *main = [[NSMenu alloc] initWithTitle: @"Turin"], *m;
	NSUInteger i;
	m = [[NSMenu alloc] initWithTitle: @"Turin"];
	add_item(m, @"About Turin", @selector(showAbout:), nil, self);
	add_item(m, @"Hide Turin", @selector(hide:), @"h", NSApp);
	add_item(m, @"Quit Turin", @selector(terminate:), @"q", NSApp);
	[main setSubmenu: m forItem: add_item(main, @"Turin", NULL, nil, nil)]; [m release];

	m = [[NSMenu alloc] initWithTitle: @"Edit"];
	add_item(m, @"Cut", @selector(cut:), @"x", nil);
	add_item(m, @"Copy", @selector(copy:), @"c", nil);
	add_item(m, @"Paste", @selector(paste:), @"v", nil);
	add_item(m, @"Select All", @selector(selectAll:), @"a", nil);
	[main setSubmenu: m forItem: add_item(main, @"Edit", NULL, nil, nil)]; [m release];

	m = [[NSMenu alloc] initWithTitle: @"View"];
	for (i = 0; i < [[window panes] count]; i++) {
		NSMenuItem *it = add_item(m, [[[window panes] objectAtIndex: i] title], @selector(showPane:),
		                          [NSString stringWithFormat: @"%lu", (unsigned long)i + 1], self);
		[it setTag: i];
	}
	[main setSubmenu: m forItem: add_item(main, @"View", NULL, nil, nil)]; [m release];

	m = [[NSMenu alloc] initWithTitle: @"Window"];
	add_item(m, @"Minimize", @selector(performMiniaturize:), @"m", nil);
	add_item(m, @"Close", @selector(performClose:), @"w", nil);
	[main setSubmenu: m forItem: add_item(main, @"Window", NULL, nil, nil)]; [m release];

	[NSApp setMainMenu: main];
	[main release];
}

- (void) applicationDidFinishLaunching: (NSNotification *)n
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	NSArray *panes = [NSArray arrayWithObjects: [[[TurinWifiPane alloc] init] autorelease],
	                  [[[TurinNetworkPane alloc] init] autorelease], [[[TurinDateTimePane alloc] init] autorelease],
	                  [[[TurinBackgroundPane alloc] init] autorelease], [[[TurinUsersPane alloc] init] autorelease], nil];
	NSInteger start;
	window = [[TurinWindow alloc] initWithPanes: panes];
	[self buildMenus];
	start = [window indexOfPaneNamed: [d stringForKey: @"TurinPane"]];
	if (start < 0) start = [window indexOfPaneNamed: [d stringForKey: @"TurinLastPane"]];
	[window showPaneAtIndex: start < 0 ? 0 : start];
	[[window window] makeKeyAndOrderFront: nil];
}

/* closing the window ends Turin, as System Preferences does */
- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *)a { return YES; }

@end

int
main(int argc, const char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	TurinApp *delegate;
	[NSApplication sharedApplication];
	delegate = [[TurinApp alloc] init];
	[NSApp setDelegate: delegate];
	[NSApp run];
	[pool release];
	return 0;
}

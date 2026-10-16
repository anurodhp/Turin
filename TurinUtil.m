#import "TurinUtil.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

@interface TurinBlockBox : NSObject { void (^block)(void); }
- (id) initWithBlock: (void (^)(void))b;
- (void) fire;
@end

@implementation TurinBlockBox
- (id) initWithBlock: (void (^)(void))b { if ((self = [super init])) block = Block_copy(b); return self; }
- (void) fire { block(); }
- (void) dealloc { Block_release(block); [super dealloc]; }
@end

void
TurinRunOnMain(void (^block)(void))
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	TurinBlockBox *b = [[TurinBlockBox alloc] initWithBlock: block];
	[b performSelectorOnMainThread: @selector(fire) withObject: nil waitUntilDone: NO];
	[b release];
	[pool release];
}

int
TurinRun(NSArray *args, NSString *input, NSString **output)
{
	NSUInteger n = [args count], i;
	char **argv;
	int in[2] = { -1, -1 }, out[2] = { -1, -1 }, st = 0;
	posix_spawn_file_actions_t fa;
	NSMutableData *got = [NSMutableData data];
	pid_t pid;
	int rc;
	if (output) *output = nil;
	if (!n) return -1;
	argv = calloc(n + 1, sizeof *argv);
	for (i = 0; i < n; i++) argv[i] = (char *)[[args objectAtIndex: i] UTF8String];
	if (pipe(in) != 0 || pipe(out) != 0) {
		if (in[0] >= 0) { close(in[0]); close(in[1]); }
		free(argv);
		return -1;
	}
	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_adddup2(&fa, in[0], 0);
	posix_spawn_file_actions_adddup2(&fa, out[1], 1);
	posix_spawn_file_actions_adddup2(&fa, out[1], 2);
	posix_spawn_file_actions_addclose(&fa, in[1]);
	posix_spawn_file_actions_addclose(&fa, out[0]);
	rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, environ);
	posix_spawn_file_actions_destroy(&fa);
	free(argv);
	close(in[0]);
	close(out[1]);
	if (rc != 0) { close(in[1]); close(out[0]); return -1; }
	if (input) {
		const char *s = [input UTF8String];
		size_t len = strlen(s), off = 0;
		void (*old)(int) = signal(SIGPIPE, SIG_IGN);	/* a tool that does not read its input must not kill us */
		while (off < len) {
			ssize_t w = write(in[1], s + off, len - off);
			if (w <= 0) { if (w < 0 && errno == EINTR) continue; break; }
			off += (size_t)w;
		}
		signal(SIGPIPE, old);
	}
	close(in[1]);
	for (;;) {
		char buf[1024];
		ssize_t r = read(out[0], buf, sizeof buf);
		if (r < 0 && errno == EINTR) continue;
		if (r <= 0) break;
		[got appendBytes: buf length: (NSUInteger)r];
	}
	close(out[0]);
	if (output) *output = [[[NSString alloc] initWithData: got encoding: NSUTF8StringEncoding] autorelease];
	while (waitpid(pid, &st, 0) < 0)
		if (errno != EINTR) return errno == ECHILD ? TurinStatusUnknown : -1;
	return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

NSString *
TurinToolLine(NSArray *argv)
{
	NSString *out = nil;
	NSString *line;
	int st = TurinRun(argv, nil, &out);
	if ((st != 0 && st != TurinStatusUnknown) || ![out length]) return nil;
	line = [[out componentsSeparatedByString: @"\n"] objectAtIndex: 0];
	line = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [line length] ? line : nil;
}

BOOL TurinIsRoot(void) { return geteuid() == 0; }

NSTextField *
TurinLabel(NSRect frame, NSString *text, CGFloat size, BOOL bold)
{
	NSTextField *t = [[[NSTextField alloc] initWithFrame: frame] autorelease];
	[t setStringValue: text ? text : @""];
	[t setEditable: NO];
	[t setSelectable: NO];
	[t setBezeled: NO];
	[t setBordered: NO];
	[t setDrawsBackground: NO];
	[t setFont: bold ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size]];
	return t;
}

NSTextField *
TurinField(NSRect frame, NSString *text)
{
	NSTextField *t = [[[NSTextField alloc] initWithFrame: frame] autorelease];
	[t setStringValue: text ? text : @""];
	return t;
}

NSButton *
TurinButton(NSRect frame, NSString *title, id target, SEL action)
{
	NSButton *b = [[[NSButton alloc] initWithFrame: frame] autorelease];
	[b setTitle: title];
	[b setBezelStyle: NSRoundedBezelStyle];
	[b setTarget: target];
	[b setAction: action];
	return b;
}

NSButton *
TurinCheckbox(NSRect frame, NSString *title, id target, SEL action)
{
	NSButton *b = [[[NSButton alloc] initWithFrame: frame] autorelease];
	[b setButtonType: NSSwitchButton];
	[b setTitle: title];
	[b setTarget: target];
	[b setAction: action];
	return b;
}

NSColor *
TurinAccent(void)
{
	return [NSColor colorWithCalibratedRed: 0.2 green: 0.45 blue: 0.85 alpha: 1];
}

void
TurinDrawGroup(NSRect r)
{
	NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: NSInsetRect(r, 0.5, 0.5) xRadius: 8 yRadius: 8];
	[[NSColor colorWithCalibratedWhite: 0.985 alpha: 1] set];
	[p fill];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.13] set];
	[p stroke];
}

@implementation TurinSwitch

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (void) setOn: (BOOL)v { if (v != on) { on = v; [self setNeedsDisplay: YES]; } }
- (BOOL) isOn { return on; }
- (NSInteger) state { return on ? NSOnState : NSOffState; }
- (void) setTarget: (id)t { target = t; }
- (id) target { return target; }
- (void) setAction: (SEL)a { action = a; }
- (SEL) action { return action; }
/* no cell: NSControl would ask a nil cell, which answers NO */
- (void) setEnabled: (BOOL)e { disabled = !e; [self setNeedsDisplay: YES]; }
- (BOOL) isEnabled { return !disabled; }

- (void) drawRect: (NSRect)dirty
{
	NSRect b = [self bounds], s = NSMakeRect(0, floor(NSMidY(b) - 10), 38, 20), knob;
	[[(on ? TurinAccent() : [NSColor colorWithCalibratedWhite: 0 alpha: 0.18]) colorWithAlphaComponent: disabled ? 0.4 : 1] set];
	[[NSBezierPath bezierPathWithRoundedRect: s xRadius: 10 yRadius: 10] fill];
	knob = NSMakeRect(on ? NSMaxX(s) - 18 : NSMinX(s) + 2, NSMinY(s) + 2, 16, 16);
	[[NSColor whiteColor] set];
	[[NSBezierPath bezierPathWithOvalInRect: knob] fill];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.25] set];
	[[NSBezierPath bezierPathWithOvalInRect: NSInsetRect(knob, 0.5, 0.5)] stroke];
}

- (void) mouseDown: (NSEvent *)e
{
	if (![self isEnabled]) return;
	[self setOn: !on];
	if (target && action) [NSApp sendAction: action to: target from: self];
}

@end

@implementation TurinGroupView
- (void) dealloc { [groups release]; [super dealloc]; }
- (BOOL) isFlipped { return NO; }
- (void) setGroups: (NSArray *)r { [groups release]; groups = [r copy]; [self setNeedsDisplay: YES]; }
- (void) drawRect: (NSRect)dirty
{
	NSValue *v;
	[[NSColor colorWithCalibratedWhite: 0.94 alpha: 1] set];
	NSRectFill(dirty);
	for (v in groups) TurinDrawGroup([v rectValue]);
}
@end

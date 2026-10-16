/* TurinUtil: the small helpers every pane uses -- running a system tool, handing work back to the main thread, and the
 * few drawing and control pieces (a label, a section box, an on/off switch) the panes are built from. */
#import <AppKit/AppKit.h>

/* Runs block on the main thread. The GNUstep run loop does not drain the main dispatch queue, so blocks from a
 * dispatch queue come back through performSelectorOnMainThread (as Naples does). */
void TurinRunOnMain(void (^block)(void));

/* Runs a tool (argv[0] is its absolute path, the array is nil-terminated by count) and waits for it. `input` is written
 * to its standard input when not nil; its standard output and error, together, are returned in *output when that is not
 * NULL. Returns the exit status, -1 if it could not be started, or TurinStatusUnknown when the child was reaped before
 * us: once any NSTask has run in the process (gnustep-base starts gdnc with one for distributed notifications),
 * gnustep-base reaps every child with waitpid(-1, WNOHANG) on SIGCHLD (Source/NSTask.m, as NaplesWifi.m's runTool
 * notes), so callers judge such a run by its output. */
#define TurinStatusUnknown (-2)
int TurinRun(NSArray *argv, NSString *input, NSString **output);
/* The first line a tool prints, nil if it fails or prints nothing. */
NSString *TurinToolLine(NSArray *argv);

BOOL TurinIsRoot(void);

/* An uneditable, borderless label. */
NSTextField *TurinLabel(NSRect frame, NSString *text, CGFloat size, BOOL bold);
NSTextField *TurinField(NSRect frame, NSString *text);
NSButton *TurinButton(NSRect frame, NSString *title, id target, SEL action);
NSButton *TurinCheckbox(NSRect frame, NSString *title, id target, SEL action);
NSColor *TurinAccent(void);	/* the blue of selections and switches */
/* The rounded, lightly filled box macOS groups settings in. */
void TurinDrawGroup(NSRect r);

/* A macOS-style on/off switch. Sends its action on click; -state is NSOnState or NSOffState. */
@interface TurinSwitch : NSControl {
	BOOL on, disabled;
	id target;
	SEL action;
}
- (void) setOn: (BOOL)v;
- (BOOL) isOn;
@end

/* A plain view that draws rounded group boxes behind its subviews: the rects in -setGroups:. */
@interface TurinGroupView : NSView {
	NSArray *groups;	/* NSValue rects */
}
- (void) setGroups: (NSArray *)rects;
@end

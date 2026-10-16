#import "TurinPane.h"
#import "TurinUtil.h"

@implementation TurinPane

- (void) dealloc { [view release]; [super dealloc]; }
- (NSString *) title { return @""; }
- (TurinIconKind) icon { return TurinIconWifi; }
- (void) loadView: (NSView *)v {}
- (void) didShow {}
- (void) didHide {}

- (NSView *) view
{
	if (!view) {
		view = [[TurinGroupView alloc] initWithFrame: NSMakeRect(0, 0, TurinPaneWidth, TurinPaneHeight)];
		[view addSubview: TurinLabel(NSMakeRect(24, TurinPaneHeight - 46, 400, 26), [self title], 19, YES)];
		[self loadView: view];
	}
	return view;
}

@end

/* ---- the dialog ---- */

NSDictionary *
TurinDialogField(NSString *label, NSString *value, BOOL secure)
{
	return [NSDictionary dictionaryWithObjectsAndKeys: label, @"label", value ? value : @"", @"value",
	        [NSNumber numberWithBool: secure], @"secure", nil];
}

enum { DialogW = 400, FieldH = 24, FieldGap = 10, LabelW = 120 };

@interface TurinDialogView : NSView <NSTextFieldDelegate> {
@public
	NSString *title, *message, *error;
	NSMutableArray *fields;
	NSButton *check, *okButton, *cancelButton;
	TurinDialogDone done;
	NSRect box;
	CGFloat messageH;
}
@end

static TurinDialogView *active;

@implementation TurinDialogView

- (id) initWithFrame: (NSRect)f title: (NSString *)t message: (NSString *)m fields: (NSArray *)specs
            checkbox: (NSString *)cb checked: (BOOL)checked okTitle: (NSString *)ok completion: (TurinDialogDone)d
{
	NSDictionary *spec;
	CGFloat h, y;
	NSUInteger i;
	if (!(self = [super initWithFrame: f])) return nil;
	title = [t copy]; message = [m copy]; done = [d copy];
	fields = [[NSMutableArray alloc] init];
	messageH = [m length] ? 18 * ceil([m length] / 58.0) + 6 : 0;
	h = 58 + messageH + 18 /* error line */ + [specs count] * (FieldH + FieldGap) + (cb ? 28 : 0) + 50;
	box = NSMakeRect(floor(NSMidX(f) - DialogW / 2), floor(NSMidY(f) - h / 2), DialogW, h);
	[self setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
	y = NSMaxY(box) - 58 - messageH - 18;
	for (i = 0; i < [specs count]; i++) {
		NSTextField *label, *field;
		spec = [specs objectAtIndex: i];
		y -= FieldH;
		label = TurinLabel(NSMakeRect(NSMinX(box) + 18, y + 3, LabelW - 8, 18), [spec objectForKey: @"label"], 12, NO);
		[label setAlignment: NSRightTextAlignment];
		[self addSubview: label];
		field = [[spec objectForKey: @"secure"] boolValue]
		    ? [[[NSSecureTextField alloc] initWithFrame: NSMakeRect(NSMinX(box) + 18 + LabelW, y, DialogW - 36 - LabelW, FieldH)] autorelease]
		    : [[[NSTextField alloc] initWithFrame: NSMakeRect(NSMinX(box) + 18 + LabelW, y, DialogW - 36 - LabelW, FieldH)] autorelease];
		[field setStringValue: [spec objectForKey: @"value"]];
		[field setDelegate: self];
		[self addSubview: field];
		[fields addObject: field];
		y -= FieldGap;
	}
	if (cb) {
		y -= 24;
		check = TurinCheckbox(NSMakeRect(NSMinX(box) + 18 + ([specs count] ? LabelW : 0), y, 260, 20), cb, nil, NULL);
		[check setState: checked ? NSOnState : NSOffState];
		[self addSubview: check];
	}
	cancelButton = TurinButton(NSMakeRect(NSMaxX(box) - 200, NSMinY(box) + 14, 90, 26), @"Cancel", self, @selector(cancel:));
	okButton = TurinButton(NSMakeRect(NSMaxX(box) - 104, NSMinY(box) + 14, 90, 26), ok, self, @selector(accept:));
	[okButton setKeyEquivalent: @"\r"];
	[self addSubview: cancelButton];
	[self addSubview: okButton];
	return self;
}

- (void) dealloc
{
	[title release]; [message release]; [error release]; [fields release]; [done release];
	[super dealloc];
}

- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstResponder { return YES; }
- (void) mouseDown: (NSEvent *)ev {}	/* clicks outside the box do nothing */

- (void) drawRect: (NSRect)dirty
{
	NSDictionary *tt = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 14], NSFontAttributeName,
	    [NSColor blackColor], NSForegroundColorAttributeName, nil];
	NSMutableParagraphStyle *ps = [[[NSMutableParagraphStyle alloc] init] autorelease];
	NSDictionary *mt, *et;
	[ps setLineBreakMode: NSLineBreakByWordWrapping];
	mt = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 12], NSFontAttributeName,
	    [NSColor colorWithCalibratedWhite: 0.2 alpha: 1], NSForegroundColorAttributeName, ps, NSParagraphStyleAttributeName, nil];
	et = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	    [NSColor colorWithCalibratedRed: 0.8 green: 0.15 blue: 0.12 alpha: 1], NSForegroundColorAttributeName, nil];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.3] set];
	NSRectFillUsingOperation([self bounds], NSCompositeSourceOver);
	[[NSColor colorWithCalibratedWhite: 0.96 alpha: 1] set];
	[[NSBezierPath bezierPathWithRoundedRect: box xRadius: 10 yRadius: 10] fill];
	[[NSColor colorWithCalibratedWhite: 0 alpha: 0.4] set];
	[[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(box, 0.5, 0.5) xRadius: 10 yRadius: 10] stroke];
	[title drawAtPoint: NSMakePoint(NSMinX(box) + 18, NSMaxY(box) - 34) withAttributes: tt];
	if ([message length])
		[message drawInRect: NSMakeRect(NSMinX(box) + 18, NSMaxY(box) - 46 - messageH, DialogW - 36, messageH) withAttributes: mt];
	if (error) [error drawAtPoint: NSMakePoint(NSMinX(box) + 18, NSMaxY(box) - 58 - messageH - 12) withAttributes: et];
}

- (void) finish: (BOOL)ok
{
	TurinDialogDone d = [[done retain] autorelease];
	NSMutableArray *values = [NSMutableArray array];
	NSTextField *f;
	BOOL checked = check && [check state] == NSOnState;
	for (f in fields) [values addObject: [[[f stringValue] copy] autorelease]];
	if (ok && d && !d(YES, values, checked)) { [self setNeedsDisplay: YES]; return; }
	if (!ok && d) d(NO, values, checked);
	for (f in fields) [f setStringValue: @""];	/* passwords do not linger in the fields */
	[[self retain] autorelease];
	{
		NSWindow *w = [self window];
		[self removeFromSuperview];
		if (active == self) active = nil;
		[w makeFirstResponder: [w contentView]];
		[w display];
	}
}

- (void) accept: (id)s { [self finish: YES]; }
- (void) cancel: (id)s { [self finish: NO]; }

- (void) keyDown: (NSEvent *)ev
{
	NSString *k = [ev charactersIgnoringModifiers];
	unichar c = [k length] ? [k characterAtIndex: 0] : 0;
	if (c == '\r' || c == '\n' || c == 3) [self accept: nil];
	else if (c == 0x1b) [self cancel: nil];
}

/* Return / Esc in a field; Tab goes to the next field */
- (BOOL) control: (NSControl *)control textView: (NSTextView *)tv doCommandBySelector: (SEL)cmd
{
	if (cmd == @selector(insertNewline:)) { [self accept: nil]; return YES; }
	if (cmd == @selector(cancelOperation:)) { [self cancel: nil]; return YES; }
	if (cmd == @selector(insertTab:) || cmd == @selector(insertBacktab:)) {
		NSUInteger i = [fields indexOfObjectIdenticalTo: control], n = [fields count];
		if (i != NSNotFound && n) {
			i = cmd == @selector(insertTab:) ? (i + 1) % n : (i + n - 1) % n;
			[[self window] makeFirstResponder: [fields objectAtIndex: i]];
			return YES;
		}
	}
	return NO;
}

- (void) present
{
	NSWindow *w = [self window];
	if ([fields count]) {
		[w makeFirstResponder: [fields objectAtIndex: 0]];
		[[fields objectAtIndex: 0] selectText: nil];
	} else
		[w makeFirstResponder: self];
	[w display];
}

@end

@implementation TurinDialog

+ (BOOL) isActive { return active != nil; }

+ (void) showIn: (NSWindow *)w title: (NSString *)title message: (NSString *)message fields: (NSArray *)fields
       checkbox: (NSString *)checkbox checked: (BOOL)checked okTitle: (NSString *)ok completion: (TurinDialogDone)done
{
	NSView *cv = [w contentView];
	TurinDialogView *v;
	if (active) [self close];
	v = [[[TurinDialogView alloc] initWithFrame: [cv bounds] title: title message: message fields: fields
	                                   checkbox: checkbox checked: checked okTitle: ok completion: done] autorelease];
	[cv addSubview: v];
	active = v;
	[w makeKeyAndOrderFront: nil];
	[v present];
}

+ (void) showError: (NSString *)e
{
	if (!active) return;
	[active->error release];
	active->error = [e copy];
	[active setNeedsDisplay: YES];
}

+ (void) close
{
	if (active) [active cancel: nil];
}

@end

#import "TurinUsersPane.h"
#import "TurinUtil.h"
#import "crypt_des.h"
#include <grp.h>
#include <stdlib.h>
#include <pwd.h>
#include <unistd.h>

#define PW @"/usr/sbin/pw"
enum { ListW = 200, UserRowH = 48 };

/* ---- reading the accounts ---- */

/* root and the people: uid 0, and 500 up to (not including) the system's nobody/nogroup range */
static NSArray *
loadUsers(void)
{
	NSMutableArray *out = [NSMutableArray array];
	NSMutableSet *admins = [NSMutableSet set], *seen = [NSMutableSet set];
	struct group *g = getgrnam("admin");
	struct passwd *p;
	char **m;
	for (m = g ? g->gr_mem : NULL; m && *m; m++) [admins addObject: [NSString stringWithUTF8String: *m]];
	setpwent();
	while ((p = getpwent())) {
		NSString *name, *full;
		if (!(p->pw_uid == 0 || (p->pw_uid >= 500 && p->pw_uid < 60000))) continue;
		name = [NSString stringWithUTF8String: p->pw_name];
		if (!name || [seen containsObject: name]) continue;
		[seen addObject: name];
		/* the GECOS field's first part is the full name */
		full = p->pw_gecos ? [[[NSString stringWithUTF8String: p->pw_gecos] componentsSeparatedByString: @","] objectAtIndex: 0] : @"";
		if (![full length]) full = p->pw_uid == 0 ? @"System Administrator" : name;
		[out addObject: [NSDictionary dictionaryWithObjectsAndKeys: name, @"name",
		                 [NSNumber numberWithUnsignedInt: p->pw_uid], @"uid", [NSNumber numberWithUnsignedInt: p->pw_gid], @"gid",
		                 full, @"full", [NSString stringWithUTF8String: p->pw_dir ? p->pw_dir : ""], @"home",
		                 [NSString stringWithUTF8String: p->pw_shell ? p->pw_shell : ""], @"shell",
		                 [NSNumber numberWithBool: p->pw_uid == 0 || [admins containsObject: name]], @"admin", nil]];
	}
	endpwent();
	[out sortUsingComparator: ^NSComparisonResult(id a, id b) {
		return [[a objectForKey: @"uid"] compare: [b objectForKey: @"uid"]];
	}];
	return out;
}

static NSArray *
shells(void)
{
	NSMutableArray *s = [NSMutableArray array];
	NSString *f = [NSString stringWithContentsOfFile: @"/etc/shells" encoding: NSUTF8StringEncoding error: NULL], *l;
	for (l in [f componentsSeparatedByString: @"\n"]) {
		l = [l stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
		if ([l hasPrefix: @"/"] && [[NSFileManager defaultManager] isExecutableFileAtPath: l]) [s addObject: l];
	}
	if (![s count]) {
		if ([[NSFileManager defaultManager] isExecutableFileAtPath: @"/bin/bash"]) [s addObject: @"/bin/bash"];
		[s addObject: @"/bin/sh"];
	}
	return s;
}

/* pw(8)'s account names: start with a letter or _, then letters, digits, _ . -; short; no capitals (macOS's rule) */
static BOOL
validName(NSString *n)
{
	NSUInteger i, len = [n length];
	if (len < 1 || len > 31) return NO;
	for (i = 0; i < len; i++) {
		unichar c = [n characterAtIndex: i];
		BOOL ok = (c >= 'a' && c <= 'z') || c == '_' || (i > 0 && ((c >= '0' && c <= '9') || c == '.' || c == '-'));
		if (!ok) return NO;
	}
	return YES;
}

static BOOL
validFull(NSString *f)
{
	return [f rangeOfString: @":"].location == NSNotFound && [f rangeOfString: @"\n"].location == NSNotFound
	    && [f rangeOfString: @","].location == NSNotFound;
}

/* a suggested account name from a full name: "Ada Lovelace" -> "adalovelace" */
static NSString *
accountFor(NSString *full)
{
	NSMutableString *s = [NSMutableString string];
	NSUInteger i;
	full = [full lowercaseString];
	for (i = 0; i < [full length] && [s length] < 20; i++) {
		unichar c = [full characterAtIndex: i];
		if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9' && [s length])) [s appendFormat: @"%C", c];
	}
	return s;
}

/* the first free uid from 501, macOS's first user */
static uid_t
nextUID(void)
{
	uid_t u = 501;
	while (getpwuid(u) && u < 60000) u++;
	return u;
}

/* The image's password hash (extended DES, crypt_des.c), nil if it cannot be made. pw(8) gets it with -H 0. */
static NSString *
hashPassword(NSString *password)
{
	char out[64];
	static BOOL seeded;
	NSString *h;
	if (!seeded) { li_crypt_seed(((unsigned long)arc4random() << 32) | arc4random()); seeded = YES; }
	if (!li_hash_password([password UTF8String], out, sizeof out)) return nil;
	h = [NSString stringWithUTF8String: out];
	memset(out, 0, sizeof out);
	return h;
}

/* runs pw with its arguments; nil on success, else what it said */
static NSString *
runPW(NSArray *a, NSString *input)
{
	NSString *out = nil, *line;
	NSMutableArray *said = [NSMutableArray array];
	int st = TurinRun([[NSArray arrayWithObject: PW] arrayByAddingObjectsFromArray: a], input, &out);
	/* useradd and usermod always warn that they cannot pick sha512 (pw_user.c login_setcryptfmt; this crypt(3) is
	 * DES only, iokit's pw_crypt_set_format_compat.c); that is not a failure */
	for (line in [out componentsSeparatedByString: @"\n"])
		if ([line length] && [line rangeOfString: @"setting crypt(3) format"].location == NSNotFound) [said addObject: line];
	out = [said componentsJoinedByString: @" "];
	/* pw says nothing when it succeeds, so a run whose status was taken by gnustep-base's reaper is judged by that */
	if (st == 0 || (st == TurinStatusUnknown && ![out length])) return nil;
	if ([out hasPrefix: @"pw: "]) out = [out substringFromIndex: 4];
	if (st < 0 && ![out length]) return [NSString stringWithFormat: @"%@ could not be run.", PW];
	return [out length] ? out : [NSString stringWithFormat: @"pw failed (status %d).", st];
}

/* ---- the list ---- */

@interface TurinUserList : NSView { TurinUsersPane *pane; }
- (id) initWithFrame: (NSRect)f pane: (TurinUsersPane *)p;
@end

@implementation TurinUserList

- (id) initWithFrame: (NSRect)f pane: (TurinUsersPane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (NSRect) rowRect: (NSUInteger)i { return NSMakeRect(6, NSHeight([self bounds]) - 6 - (i + 1) * UserRowH, NSWidth([self bounds]) - 12, UserRowH - 2); }

- (void) drawRect: (NSRect)dirty
{
	NSArray *u = [pane users];
	NSUInteger i;
	uid_t me = getuid();
	for (i = 0; i < [u count]; i++) {
		NSDictionary *d = [u objectAtIndex: i];
		NSRect r = [self rowRect: i];
		BOOL sel = (NSInteger)i == [pane selected];
		NSDictionary *na = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName,
		                    sel ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0.08 alpha: 1], NSForegroundColorAttributeName, nil];
		NSDictionary *sa = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 10], NSFontAttributeName,
		                    sel ? [NSColor colorWithCalibratedWhite: 1 alpha: 0.85] : [NSColor colorWithCalibratedWhite: 0 alpha: 0.5],
		                    NSForegroundColorAttributeName, nil];
		NSString *kind = [[d objectForKey: @"uid"] unsignedIntValue] == 0 ? @"System" : [[d objectForKey: @"admin"] boolValue] ? @"Admin" : @"Standard";
		if ([[d objectForKey: @"uid"] unsignedIntValue] == me) kind = [kind stringByAppendingString: @" · You"];
		if (sel) {
			[TurinAccent() set];
			[[NSBezierPath bezierPathWithRoundedRect: r xRadius: 6 yRadius: 6] fill];
		}
		TurinDrawAvatar(NSMakeRect(NSMinX(r) + 6, NSMidY(r) - 16, 32, 32), [d objectForKey: @"full"]);
		[[d objectForKey: @"full"] drawInRect: NSMakeRect(NSMinX(r) + 46, NSMidY(r) + 1, NSWidth(r) - 50, 17) withAttributes: na];
		[kind drawAtPoint: NSMakePoint(NSMinX(r) + 46, NSMidY(r) - 15) withAttributes: sa];
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
	NSUInteger i;
	for (i = 0; i < [[pane users] count]; i++)
		if (NSPointInRect(p, [self rowRect: i])) { [pane select: i]; return; }
}

@end

@interface TurinAvatarView : NSView { NSString *name; }
- (void) setName: (NSString *)n;
@end

@implementation TurinAvatarView
- (void) dealloc { [name release]; [super dealloc]; }
- (void) setName: (NSString *)n { if (n != name) { [name release]; name = [n copy]; } [self setNeedsDisplay: YES]; }
- (void) drawRect: (NSRect)dirty { if (name) TurinDrawAvatar([self bounds], name); }
@end

/* ---- the pane ---- */

@implementation TurinUsersPane

- (NSString *) title { return @"Users"; }
- (TurinIconKind) icon { return TurinIconUsers; }
- (NSArray *) users { return users; }
- (NSInteger) selected { return selected; }

- (void) dealloc
{
	[users release]; [listView release]; [avatarView release]; [nameLabel release]; [accountLabel release];
	[fullField release]; [uidLabel release]; [homeLabel release]; [message release]; [shellPopup release];
	[adminBox release]; [passwordButton release]; [saveButton release]; [addButton release]; [removeButton release];
	[super dealloc];
}

- (NSDictionary *) current
{
	return selected >= 0 && selected < (NSInteger)[users count] ? [users objectAtIndex: selected] : nil;
}

- (void) say: (NSString *)s error: (BOOL)err
{
	[message setStringValue: s ? s : @""];
	[message setTextColor: err ? [NSColor colorWithCalibratedRed: 0.8 green: 0.15 blue: 0.12 alpha: 1]
	                           : [NSColor colorWithCalibratedWhite: 0 alpha: 0.55]];
}

- (void) reloadSelecting: (NSString *)name
{
	NSUInteger i;
	NSString *was = [(name ? name : [[self current] objectForKey: @"name"]) retain];	/* outlives the old list */
	[users release];
	users = [loadUsers() retain];
	selected = [users count] ? 0 : -1;
	for (i = 0; was && i < [users count]; i++)
		if ([[[users objectAtIndex: i] objectForKey: @"name"] isEqual: was]) selected = i;
	[was release];
	[self select: selected];
}

- (void) select: (NSInteger)i
{
	NSDictionary *u;
	BOOL root = TurinIsRoot(), isRoot, isMe;
	NSString *sh;
	selected = i;
	u = [self current];
	isRoot = [[u objectForKey: @"uid"] unsignedIntValue] == 0;
	isMe = [[u objectForKey: @"uid"] unsignedIntValue] == getuid();
	[(TurinAvatarView *)avatarView setName: [u objectForKey: @"full"]];
	[nameLabel setStringValue: u ? [u objectForKey: @"full"] : @""];
	[accountLabel setStringValue: u ? [u objectForKey: @"name"] : @""];
	[fullField setStringValue: u ? [u objectForKey: @"full"] : @""];
	[uidLabel setStringValue: u ? [[u objectForKey: @"uid"] stringValue] : @""];
	[homeLabel setStringValue: u ? [u objectForKey: @"home"] : @""];
	sh = [u objectForKey: @"shell"];
	[shellPopup removeAllItems];
	[shellPopup addItemsWithTitles: shells()];
	if ([sh length] && [shellPopup indexOfItemWithTitle: sh] < 0) [shellPopup addItemWithTitle: sh];
	if ([sh length]) [shellPopup selectItemWithTitle: sh];
	[adminBox setState: [[u objectForKey: @"admin"] boolValue] ? NSOnState : NSOffState];
	[fullField setEnabled: root && u];
	[shellPopup setEnabled: root && u];
	[adminBox setEnabled: root && u && !isRoot];	/* root is always an administrator */
	[passwordButton setEnabled: root && u];
	[saveButton setEnabled: root && u];
	[addButton setEnabled: root];
	[removeButton setEnabled: root && u && !isRoot && !isMe];
	[self say: root ? nil : @"Only the root account can add, change or remove users." error: NO];
	[listView setNeedsDisplay: YES];
}

- (void) save: (id)sender
{
	NSDictionary *u = [self current];
	NSString *name = [u objectForKey: @"name"], *full = [[fullField stringValue] stringByTrimmingCharactersInSet:
	                     [NSCharacterSet whitespaceCharacterSet]], *shell = [shellPopup titleOfSelectedItem], *err = nil;
	BOOL admin = [adminBox state] == NSOnState;
	NSMutableArray *a;
	if (!u) return;
	if (!validFull(full)) { [self say: @"A full name cannot contain “:” or “,”." error: YES]; return; }
	a = [NSMutableArray arrayWithObjects: @"usermod", name, nil];
	if (![full isEqual: [u objectForKey: @"full"]]) [a addObjectsFromArray: [NSArray arrayWithObjects: @"-c", full, nil]];
	if (shell && ![shell isEqual: [u objectForKey: @"shell"]]) [a addObjectsFromArray: [NSArray arrayWithObjects: @"-s", shell, nil]];
	if ([a count] > 2) err = runPW(a, nil);
	if (!err && [[u objectForKey: @"uid"] unsignedIntValue] != 0 && admin != [[u objectForKey: @"admin"] boolValue])
		err = runPW([NSArray arrayWithObjects: @"groupmod", @"admin", admin ? @"-m" : @"-d", name, nil], nil);
	[self reloadSelecting: name];
	[self say: err ? err : @"Saved." error: err != nil];
}

- (void) changePassword: (id)sender
{
	NSString *name = [[self current] objectForKey: @"name"];
	if (!name) return;
	[TurinDialog showIn: [view window] title: [NSString stringWithFormat: @"Change the password of “%@”", [[self current] objectForKey: @"full"]]
	            message: nil
	             fields: [NSArray arrayWithObjects: TurinDialogField(@"New Password:", @"", YES), TurinDialogField(@"Verify:", @"", YES), nil]
	           checkbox: nil checked: NO okTitle: @"Change"
	         completion: ^BOOL(BOOL ok, NSArray *v, BOOL checked) {
		NSString *err, *hash;
		if (!ok) return YES;
		if (![[v objectAtIndex: 0] length]) { [TurinDialog showError: @"Enter a password."]; return NO; }
		if (![[v objectAtIndex: 0] isEqual: [v objectAtIndex: 1]]) { [TurinDialog showError: @"The passwords do not match."]; return NO; }
		if ([[v objectAtIndex: 0] rangeOfString: @"\n"].location != NSNotFound) { [TurinDialog showError: @"A password is one line."]; return NO; }
		if (!(hash = hashPassword([v objectAtIndex: 0]))) { [TurinDialog showError: @"The password could not be hashed."]; return NO; }
		/* -H 0: pw reads the hashed password from its standard input */
		err = runPW([NSArray arrayWithObjects: @"usermod", name, @"-H", @"0", nil], [hash stringByAppendingString: @"\n"]);
		if (err) { [TurinDialog showError: err]; return NO; }
		[self say: [NSString stringWithFormat: @"The password of %@ was changed.", name] error: NO];
		return YES;
	}];
}

- (void) addUser: (id)sender
{
	[TurinDialog showIn: [view window] title: @"New User"
	            message: @"The account name is used for the home folder (/Users/name) and for logging in. It cannot be changed later."
	             fields: [NSArray arrayWithObjects: TurinDialogField(@"Full Name:", @"", NO), TurinDialogField(@"Account Name:", @"", NO),
	                      TurinDialogField(@"Password:", @"", YES), TurinDialogField(@"Verify:", @"", YES), nil]
	           checkbox: @"Allow user to administer this computer" checked: NO okTitle: @"Create User"
	         completion: ^BOOL(BOOL ok, NSArray *v, BOOL admin) {
		NSString *full = [[v objectAtIndex: 0] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
		NSString *name = [v objectAtIndex: 1], *pw = [v objectAtIndex: 2], *err, *hash;
		NSString *shell = [[NSFileManager defaultManager] isExecutableFileAtPath: @"/bin/bash"] ? @"/bin/bash" : @"/bin/sh";
		NSMutableArray *a;
		if (!ok) return YES;
		if (![name length]) name = accountFor(full);
		if (![full length]) full = name;
		if (!validName(name)) {
			[TurinDialog showError: @"Account names use a–z, 0–9, “_”, “.” and “-”, starting with a letter."];
			return NO;
		}
		if (getpwnam([name UTF8String])) { [TurinDialog showError: [NSString stringWithFormat: @"There is already a user “%@”.", name]]; return NO; }
		if (!validFull(full)) { [TurinDialog showError: @"A full name cannot contain “:” or “,”."]; return NO; }
		if (![pw length]) { [TurinDialog showError: @"Enter a password."]; return NO; }
		if (![pw isEqual: [v objectAtIndex: 3]]) { [TurinDialog showError: @"The passwords do not match."]; return NO; }
		if ([pw rangeOfString: @"\n"].location != NSNotFound) { [TurinDialog showError: @"A password is one line."]; return NO; }
		if (!(hash = hashPassword(pw))) { [TurinDialog showError: @"The password could not be hashed."]; return NO; }
		/* uids from 501 and staff (20) as the primary group, as on macOS (pw's own default starts at 1000); -m makes the home folder under pw.conf's /Users; -H 0
		 * reads the hashed password from standard input */
		a = [NSMutableArray arrayWithObjects: @"useradd", name, @"-u", [NSString stringWithFormat: @"%u", nextUID()],
		     @"-c", full, @"-g", @"staff", @"-m", @"-s", shell, @"-H", @"0", nil];
		if (admin) [a addObjectsFromArray: [NSArray arrayWithObjects: @"-G", @"admin", nil]];
		err = runPW(a, [hash stringByAppendingString: @"\n"]);
		if (err) { [TurinDialog showError: err]; return NO; }
		[self reloadSelecting: name];
		[self say: [NSString stringWithFormat: @"Created %@ (%@).", full, name] error: NO];
		return YES;
	}];
}

- (void) removeUser: (id)sender
{
	NSDictionary *u = [self current];
	NSString *name = [u objectForKey: @"name"], *home = [u objectForKey: @"home"];
	if (!u || [[u objectForKey: @"uid"] unsignedIntValue] == 0 || [[u objectForKey: @"uid"] unsignedIntValue] == getuid()) return;
	[TurinDialog showIn: [view window] title: [NSString stringWithFormat: @"Delete the user “%@”?", [u objectForKey: @"full"]]
	            message: [NSString stringWithFormat: @"The account %@ is removed and can no longer log in. Its home folder %@ is kept unless you tick the box.", name, home]
	             fields: nil checkbox: @"Also delete the home folder" checked: NO okTitle: @"Delete User"
	         completion: ^BOOL(BOOL ok, NSArray *v, BOOL removeHome) {
		NSString *err;
		if (!ok) return YES;
		err = runPW(removeHome ? [NSArray arrayWithObjects: @"userdel", name, @"-r", nil] : [NSArray arrayWithObjects: @"userdel", name, nil], nil);
		if (err) { [TurinDialog showError: err]; return NO; }
		[self reloadSelecting: nil];
		[self say: [NSString stringWithFormat: @"Deleted %@.", name] error: NO];
		return YES;
	}];
}

static NSTextField *
formLabel(NSView *v, CGFloat y, NSString *s)
{
	NSTextField *l = TurinLabel(NSMakeRect(20 + ListW + 20, y + 3, 110, 18), s, 12, NO);
	[l setAlignment: NSRightTextAlignment];
	[v addSubview: l];
	return l;
}

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth, X = 20 + ListW + 138, FW = W - 40 - X;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 56, ListW, 444)],
	    [NSValue valueWithRect: NSMakeRect(20 + ListW + 12, 16, W - 52 - ListW, 484)], nil]];
	listView = [[TurinUserList alloc] initWithFrame: NSMakeRect(20, 56, ListW, 444) pane: self];
	[v addSubview: listView];
	addButton = [TurinButton(NSMakeRect(20, 18, 34, 28), @"+", self, @selector(addUser:)) retain];
	removeButton = [TurinButton(NSMakeRect(58, 18, 34, 28), @"−", self, @selector(removeUser:)) retain];
	[v addSubview: addButton];
	[v addSubview: removeButton];

	avatarView = [[TurinAvatarView alloc] initWithFrame: NSMakeRect(20 + ListW + 30, 418, 64, 64)];
	[v addSubview: avatarView];
	nameLabel = [TurinLabel(NSMakeRect(20 + ListW + 108, 452, W - ListW - 160, 24), @"", 17, YES) retain];
	accountLabel = [TurinLabel(NSMakeRect(20 + ListW + 108, 432, W - ListW - 160, 18), @"", 12, NO) retain];
	[accountLabel setTextColor: [NSColor colorWithCalibratedWhite: 0 alpha: 0.5]];
	[v addSubview: nameLabel];
	[v addSubview: accountLabel];

	formLabel(v, 370, @"Full Name:");
	fullField = [TurinField(NSMakeRect(X, 370, FW, 24), @"") retain];
	[v addSubview: fullField];
	formLabel(v, 336, @"User ID:");
	uidLabel = [TurinLabel(NSMakeRect(X, 339, FW, 18), @"", 12, NO) retain];
	[v addSubview: uidLabel];
	formLabel(v, 306, @"Home Folder:");
	homeLabel = [TurinLabel(NSMakeRect(X, 309, FW, 18), @"", 12, NO) retain];
	[v addSubview: homeLabel];
	formLabel(v, 270, @"Login Shell:");
	shellPopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(X, 268, 150, 26) pullsDown: NO];
	[v addSubview: shellPopup];
	formLabel(v, 232, @"Account Type:");
	adminBox = [TurinCheckbox(NSMakeRect(X, 232, FW, 22), @"Administrator", nil, NULL) retain];
	[v addSubview: adminBox];
	passwordButton = [TurinButton(NSMakeRect(X, 186, 160, 26), @"Change Password…", self, @selector(changePassword:)) retain];
	[v addSubview: passwordButton];
	saveButton = [TurinButton(NSMakeRect(W - 40 - 90, 30, 90, 26), @"Save", self, @selector(save:)) retain];
	[v addSubview: saveButton];
	message = [TurinLabel(NSMakeRect(20 + ListW + 30, 66, W - ListW - 80, 32), @"", 11, NO) retain];
	[v addSubview: message];
	selected = -1;
	[self reloadSelecting: nil];
}

- (void) didShow { [self reloadSelecting: nil]; }

@end

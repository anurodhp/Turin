/* TurinUsersPane: the accounts on the system -- list, add, change (full name, shell, administrator, password) and
 * delete. Changes go through the image's FreeBSD pw(8) (/usr/sbin/pw, iokit's build_pw.sh), which edits
 * /etc/master.passwd and /etc/group and rebuilds the password databases with pwd_mkdb; new accounts get their home
 * folder under /Users (/etc/pw.conf). An administrator is a member of the "admin" group (gid 80), as on macOS.
 * Changing accounts needs root: for anyone else the pane only lists them. */
#import "TurinPane.h"

@interface TurinUsersPane : TurinPane {
	NSArray *users;	/* NSDictionary {name, uid, gid, full, home, shell, admin} */
	NSInteger selected;
	NSView *listView, *avatarView;
	NSTextField *nameLabel, *accountLabel, *fullField, *uidLabel, *homeLabel, *message;
	NSPopUpButton *shellPopup;
	NSButton *adminBox, *passwordButton, *saveButton, *addButton, *removeButton;
}
- (NSArray *) users;
- (NSInteger) selected;
- (void) select: (NSInteger)i;
@end

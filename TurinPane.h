/* TurinPane: one page of the window (Wi-Fi, Network, Date & Time, Background, Users). The window lists the panes in the
 * sidebar and shows one at a time in the area to its right. */
#import <AppKit/AppKit.h>
#import "TurinIcons.h"

#define TurinPaneWidth 590.0
#define TurinPaneHeight 560.0

@interface TurinPane : NSObject {
	NSView *view;
}
- (NSString *) title;
- (TurinIconKind) icon;
- (NSView *) view;	/* made on first use with -loadView: */
- (void) loadView: (NSView *)v;	/* subclasses add their controls to v (TurinPaneWidth x TurinPaneHeight, unflipped) */
- (void) didShow;	/* it became the visible pane: start refreshing */
- (void) didHide;	/* stop refreshing */
@end

/* Confirmation and form dialogs drawn over the window's content (Milan's MilanDialog: Eau shows NSAlerts without waiting
 * for an answer, and Naples found NSRunAlertPanel does not appear on this stack). Not modal; one at a time.
 * fields: NSDictionary {label, value, secure (NSNumber BOOL)}; checkbox: its title, nil for none. The completion gets the
 * fields' values in order and the checkbox state; on OK it returns NO to keep the dialog open (after +showError:), YES
 * to close it. Return accepts, Esc cancels. */
typedef BOOL (^TurinDialogDone)(BOOL ok, NSArray *values, BOOL checked);

@interface TurinDialog : NSObject
+ (void) showIn: (NSWindow *)w title: (NSString *)title message: (NSString *)message fields: (NSArray *)fields
       checkbox: (NSString *)checkbox checked: (BOOL)checked okTitle: (NSString *)ok completion: (TurinDialogDone)done;
/* An error shown under the message, for a completion that returns NO. */
+ (void) showError: (NSString *)error;
+ (BOOL) isActive;
+ (void) close;
@end

NSDictionary *TurinDialogField(NSString *label, NSString *value, BOOL secure);

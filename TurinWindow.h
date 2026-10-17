/* TurinWindow: the Settings window -- the sidebar of panes on the left, the chosen pane on the right. */
#import <AppKit/AppKit.h>
#import "TurinPane.h"

@interface TurinWindow : NSObject {
	NSWindow *window;
	NSArray *panes;
	NSView *sidebar;
	NSView *holder;	/* the area right of the sidebar */
	NSInteger current;
}
- (id) initWithPanes: (NSArray *)panes;
- (NSWindow *) window;
- (void) showPaneAtIndex: (NSInteger)i;
- (NSInteger) indexOfPaneNamed: (NSString *)name;	/* by title, case-insensitive; -1 if none */
- (NSArray *) panes;
- (NSInteger) currentIndex;
@end

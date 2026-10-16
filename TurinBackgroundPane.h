/* TurinBackgroundPane: Milan's desktop background -- a picture (Milan's own wallpapers and ~/Pictures), how it is
 * placed, and the colour behind it. Milan's "Desktop Background" panel (MilanWallpaper.m) in a pane.
 *
 * The settings are Milan's: its defaults domain (MilanWallpaperPath, MilanWallpaperFill, MilanWallpaperColor), written
 * here and announced with the distributed notification MilanWallpaperChanged, on which Milan re-reads them and redraws
 * the desktop. Milan posts the same notification when its own panel changes them, and this pane follows. */
#import "TurinPane.h"

typedef enum { TurinFillFill, TurinFillFit, TurinFillStretch, TurinFillCenter, TurinFillTile } TurinFill;	/* MilanFill */

@interface TurinBackgroundPane : TurinPane {
	NSString *imagePath;	/* nil: a plain colour */
	NSColor *color;
	TurinFill fill;
	NSView *preview, *thumbs, *swatches;
	NSScrollView *scroll;
	NSSegmentedControl *placement;
	NSTextField *note;
}
- (NSString *) imagePath;
- (NSColor *) color;
- (TurinFill) fill;
- (void) setImagePath: (NSString *)p fill: (TurinFill)f color: (NSColor *)c;	/* saves into Milan's domain and tells Milan */
+ (NSArray *) availablePictures;
@end

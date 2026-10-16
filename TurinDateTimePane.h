/* TurinDateTimePane: the date and time (an analog clock, a month calendar and a time field; Set applies them with
 * settimeofday), the time zone (the IANA zones of the system's zone.tab, by region and city) and the language and
 * region (the GNUstep "Locale" and "NSLanguages" defaults). */
#import "TurinPane.h"
#import "TurinUtil.h"

@interface TurinDateTimePane : TurinPane <NSTextFieldDelegate> {
	NSView *clockView, *calendarView;
	NSTextField *timeField, *dateLabel, *syncLabel, *dateMessage;
	NSButton *setButton, *revertButton;
	BOOL editing;	/* the controls hold a date the user is choosing, not the current one */
	int year, month, day;	/* the chosen date while editing (month 1-12) */
	dispatch_source_t timer;

	NSDictionary *zones;	/* region -> sorted array of zone names under it */
	NSPopUpButton *regionPopup, *cityPopup;
	NSTextField *zoneLabel, *zoneMessage;
	NSButton *zoneButton;

	NSPopUpButton *localePopup;
	NSTextField *localeLabel;
	NSButton *localeButton;
}
/* for the views */
- (BOOL) editing;
- (int) year;
- (int) month;
- (int) day;
- (void) setYear: (int)y month: (int)m day: (int)d;
- (struct tm) shownTime;	/* what the clock should show */
@end

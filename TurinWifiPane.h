/* TurinWifiPane: Wi-Fi on/off, the network in use with its details, and the networks in range to join. */
#import "TurinPane.h"
#import "TurinWifi.h"
#import "TurinUtil.h"

@interface TurinWifiPane : TurinPane {
	TurinWifi *wifi;
	TurinSwitch *power;
	NSTextField *status;
	NSView *current;	/* the connected network and its details */
	NSView *list;	/* the other networks */
	NSScrollView *scroll;
	NSButton *disconnectButton, *forgetButton, *joinButton, *scanButton, *otherButton;
	NSTextField *scanLabel;
}
@end

/* TurinNetworkPane: the network interfaces (Ethernet, Wi-Fi, ...) with their state, and the current connection's
 * details: addresses, router, DNS, hardware address, traffic. Read-only. */
#import "TurinPane.h"

@interface TurinNetworkPane : TurinPane {
	NSArray *interfaces;	/* NSDictionary per interface, see TurinNetworkPane.m's gather() */
	NSString *hostname;
	NSArray *dns, *searchDomains;
	NSInteger selected;
	NSView *listView, *detailView;
	dispatch_queue_t queue;
	dispatch_source_t timer;
	BOOL gathering;
}
- (NSArray *) interfaces;
- (NSInteger) selected;
- (void) select: (NSInteger)i;
- (NSString *) hostname;
- (NSArray *) dns;
- (NSArray *) searchDomains;
@end

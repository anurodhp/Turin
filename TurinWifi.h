/* TurinWifi: Wi-Fi state and actions, the model half of Naples' NaplesWifi.m with its menu-bar panel left out.
 *
 * It talks to iokit's BCM43430Wifi driver directly, through its user client (the ABI in iokit's
 * iokit/BCM43430Wifi/BCM43430WifiShared.h, the same one /usr/sbin/wifi and Naples use), with IOKitLib opened by dlopen
 * from /usr/lib/libiokituser.dylib. Every call can block (a scan takes seconds, a join up to 20 s), so they run on a
 * serial queue, never on the main thread; the change handler runs on the main thread.
 *
 * The driver's methods other than status need root. Joining remembers the network in /etc/wifi.conf (mode 600), which
 * the boot job org.puredarwin.wifi joins at startup; turning Wi-Fi off leaves /etc/wifi.off, which keeps the radio off
 * at the next boot. The address comes from IPConfiguration (`ipconfig set en1 DHCP`) after a join. Naples and Turin
 * keep no state of their own beyond these files, so either one shows what the other did at its next poll. */
#import <AppKit/AppKit.h>

@interface TurinWifi : NSObject {
	void (^changed)(void);
	dispatch_queue_t queue;
	unsigned int conn;	/* io_connect_t, used on `queue` only */
	BOOL available;	/* libiokituser loaded */
	BOOL known;	/* the driver answered */
	BOOL firmwareUp, radioOff, associated, scanning;
	int powerPending;
	uint32_t fwState;
	BOOL securedNow;
	NSString *remembered;	/* the SSID in /etc/wifi.conf */
	NSDictionary *autoJoin;
	NSString *ssid;
	int rssi;
	NSArray *networks;	/* NSDictionary {ssid, rssi, secure, channel}, strongest first, the connected one left out */
	NSString *joining;
	NSString *message;
	NSArray *details;	/* {label, value} pairs for the connected network */
	NSString *ipAddress, *router, *macAddress, *firmware;
	dispatch_source_t pollTimer;
	BOOL fast;
	NSTimeInterval lastScan;
}
- (id) initWithChangeHandler: (void (^)(void))handler;
- (BOOL) available;	/* NO: no libiokituser on this system */
- (BOOL) known;	/* NO: no answer from the driver (no wifi=1) */
- (BOOL) enabled;
- (BOOL) associated;
- (NSString *) ssid;
- (int) rssi;
- (BOOL) securedNow;
- (NSArray *) networks;
- (BOOL) scanning;
- (NSString *) joining;
- (NSString *) message;
- (NSArray *) details;
- (NSString *) remembered;
- (NSString *) macAddress;	/* the chip's, nil until known */
- (NSString *) firmware;
- (void) setEnabled: (BOOL)on;
- (void) scan;
- (void) join: (NSString *)name password: (NSString *)psk;	/* psk "" for an open network */
- (BOOL) hasSavedPasswordFor: (NSString *)name;
- (void) joinSaved: (NSString *)name;
- (void) disconnect;	/* leave, but stay remembered */
- (void) forgetCurrent;	/* leave, drop it from /etc/wifi.conf, release en1's address */
- (void) setActive: (BOOL)visible;	/* poll every 2 s and rescan every 15 s while the pane shows, else every 10 s */
- (void) setMessage: (NSString *)m;
@end

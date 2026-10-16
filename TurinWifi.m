#import "TurinWifi.h"
#import "TurinUtil.h"
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>

/* The driver's ABI, shared with the kernel, /usr/sbin/wifi and Naples (iokit's build_turin.sh puts its directory on the
 * include path). */
#import "BCM43430WifiShared.h"

/* ---- IOKitLib, by dlopen (the signatures of IOKit/IOKitLib.h; io_object_t and io_connect_t are mach ports) ---- */

typedef mach_port_t TurinIOObject;
static CFMutableDictionaryRef (*ioServiceMatching)(const char *);
static TurinIOObject (*ioGetMatchingService)(mach_port_t, CFDictionaryRef);
static kern_return_t (*ioServiceOpen)(TurinIOObject, task_port_t, uint32_t, TurinIOObject *);
static kern_return_t (*ioObjectRelease)(TurinIOObject);
static kern_return_t (*ioServiceClose)(TurinIOObject);
static kern_return_t (*ioCallMethod)(TurinIOObject, uint32_t, const uint64_t *, uint32_t, const void *, size_t,
                                     uint64_t *, uint32_t *, void *, size_t *);

/* IOReturn codes used here (IOKit/IOReturn.h: iokit_common_err(x) = 0xe0000000 | x) */
enum {
	kIOReturnNotReady     = (int)0xe00002d8,	/* the driver is not up yet (still loading firmware) */
	kIOReturnNotAttached  = (int)0xe00002d9,	/* the user client went away */
	kIOReturnNotPermitted = (int)0xe00002e2,	/* BCM43430Wifi join: WPA2 handshake failed */
};

static BOOL
loadIOKit(void)
{
	void *h = dlopen("/usr/lib/libiokituser.dylib", RTLD_LAZY | RTLD_LOCAL);
	if (!h) return NO;
	ioServiceMatching = dlsym(h, "IOServiceMatching");
	ioGetMatchingService = dlsym(h, "IOServiceGetMatchingService");
	ioServiceOpen = dlsym(h, "IOServiceOpen");
	ioObjectRelease = dlsym(h, "IOObjectRelease");
	ioServiceClose = dlsym(h, "IOServiceClose");
	ioCallMethod = dlsym(h, "IOConnectCallMethod");
	return ioServiceMatching && ioGetMatchingService && ioServiceOpen && ioObjectRelease && ioServiceClose && ioCallMethod;
}

/* ---- files (run on the queue) ---- */

#define WifiConf "/etc/wifi.conf"
#define WifiOff  "/etc/wifi.off"

/* /etc/wifi.conf: the remembered network, ssid=... and psk=... lines (wifi.c readConf()) */
static NSDictionary *
savedNetwork(void)
{
	char line[256], ssid[64] = "", psk[128] = "";
	FILE *f = fopen(WifiConf, "r");
	if (!f) return nil;
	while (fgets(line, sizeof line, f)) {
		line[strcspn(line, "\r\n")] = 0;
		if (!strncmp(line, "ssid=", 5)) strlcpy(ssid, line + 5, sizeof ssid);
		else if (!strncmp(line, "psk=", 4)) strlcpy(psk, line + 4, sizeof psk);
	}
	fclose(f);
	memset(line, 0, sizeof line);
	if (!ssid[0]) return nil;
	return [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithUTF8String: ssid], @"ssid",
	        [NSString stringWithUTF8String: psk], @"psk", nil];
}

static void
saveNetwork(const char *ssid, const char *psk)
{
	char buf[256];
	int fd, n;
	if (strchr(ssid, '\n') || strchr(psk, '\n')) return;
	n = snprintf(buf, sizeof buf, "ssid=%s\npsk=%s\n", ssid, psk);
	if (n <= 0 || n >= (int)sizeof buf) return;
	/* a fresh file only: never follow or reuse a leftover .new (it would get the passphrase) */
	unlink(WifiConf ".new");
	fd = open(WifiConf ".new", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
	if (fd < 0) { NSLog(@"Turin: cannot write %s", WifiConf); memset(buf, 0, sizeof buf); return; }
	if (write(fd, buf, n) == n && fsync(fd) == 0) {
		close(fd);
		if (rename(WifiConf ".new", WifiConf) != 0) unlink(WifiConf ".new");
	} else {
		close(fd);
		unlink(WifiConf ".new");
	}
	memset(buf, 0, sizeof buf);
}

static NSString *
interfaceAddress(const char *ifname)
{
	struct ifaddrs *ifs, *i;
	NSString *s = nil;
	if (getifaddrs(&ifs) != 0) return nil;
	for (i = ifs; i && !s; i = i->ifa_next) {
		char a[INET_ADDRSTRLEN];
		if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || strcmp(i->ifa_name, ifname)) continue;
		if (inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, a, sizeof a))
			s = [NSString stringWithUTF8String: a];
	}
	freeifaddrs(ifs);
	return s;
}

static NSArray *
args(NSString *first, ...)
{
	NSMutableArray *a = [NSMutableArray arrayWithObject: first];
	va_list ap;
	NSString *s;
	va_start(ap, first);
	while ((s = va_arg(ap, NSString *))) [a addObject: s];
	va_end(ap);
	return a;
}

@interface TurinWifi (Private)
- (void) poll;
- (void) notify;
- (void) joinName: (NSString *)name password: (NSString *)psk;
- (NSArray *) detailsFrom: (const wifi_status *)st;
@end

@implementation TurinWifi

- (id) initWithChangeHandler: (void (^)(void))handler
{
	if (!(self = [super init])) return nil;
	changed = Block_copy(handler);
	available = loadIOKit();
	if (!available) return self;
	queue = dispatch_queue_create("turin.wifi", NULL);
	pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
	dispatch_source_set_timer(pollTimer, DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC, NSEC_PER_SEC);
	dispatch_source_set_event_handler(pollTimer, ^{ TurinRunOnMain(^{ [self poll]; }); });
	dispatch_resume(pollTimer);
	return self;
}

- (BOOL) available { return available; }
- (BOOL) known { return known; }
- (BOOL) enabled { return powerPending ? !radioOff : firmwareUp && !radioOff; }
- (BOOL) associated { return associated; }
- (NSString *) ssid { return ssid; }
- (int) rssi { return rssi; }
- (BOOL) securedNow { return securedNow; }
- (NSArray *) networks { return networks; }
- (BOOL) scanning { return scanning; }
- (NSString *) joining { return joining; }
- (NSString *) message { return message; }
- (NSArray *) details { return details; }
- (NSString *) remembered { return remembered; }
- (NSString *) macAddress { return macAddress; }
- (NSString *) firmware { return firmware; }

- (void) setMessage: (NSString *)m { if (m != message) { [message release]; message = [m copy]; } }
- (void) notify { if (changed) changed(); }

- (void) setActive: (BOOL)visible
{
	if (!available) return;
	fast = visible;
	dispatch_source_set_timer(pollTimer, DISPATCH_TIME_NOW, (visible ? 2 : 10) * NSEC_PER_SEC, NSEC_PER_SEC);
	if (visible) [self scan];
}

/* on the queue: the connection to the driver, opened on first use; NO if there is no BCM43430Wifi (no wifi=1) */
- (BOOL) connected
{
	TurinIOObject svc;
	if (conn) return YES;
	svc = ioGetMatchingService(MACH_PORT_NULL, (CFDictionaryRef)ioServiceMatching(kBCM43430WifiClass));
	if (!svc) return NO;
	if (ioServiceOpen(svc, mach_task_self(), 0, &conn) != KERN_SUCCESS) conn = 0;
	ioObjectRelease(svc);
	return conn != 0;
}

- (kern_return_t) call: (uint32_t)sel scalar: (const uint64_t *)in count: (uint32_t)n
                 input: (const void *)is size: (size_t)isz output: (void *)os size: (size_t)osz
{
	size_t outSize = osz;
	kern_return_t kr = ioCallMethod(conn, sel, in, n, is, isz, NULL, NULL, os, os ? &outSize : NULL);
	if (kr == MACH_SEND_INVALID_DEST || kr == kIOReturnNotAttached) {	/* the user client is gone: open a new one next time */
		ioServiceClose(conn);
		conn = 0;
	}
	return kr;
}

- (void) poll
{
	if (!available) return;
	dispatch_async(queue, ^{
		/* the queue has no autorelease pool, and gnustep-base drops objects autoreleased without one */
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		wifi_status st;
		BOOL ok;
		NSString *ip = nil, *gw = nil, *mem = [savedNetwork() objectForKey: @"ssid"];
		memset(&st, 0, sizeof st);
		ok = [self connected] && [self call: kWifiMethodStatus scalar: NULL count: 0 input: NULL size: 0
		                                    output: &st size: sizeof st] == KERN_SUCCESS;
		if (ok && st.associated) {
			ip = interfaceAddress("en1");
			gw = TurinToolLine(args(@"/usr/sbin/ipconfig", @"getoption", @"en1", @"router", nil));
		}
		[ip retain]; [gw retain]; [mem retain];
		TurinRunOnMain(^{
			BOOL wasAssociated = associated;
			if (ok) {
				known = YES;
				fwState = st.state;
				[remembered release];
				remembered = [mem copy];
				firmwareUp = st.state == kWifiStateUp;
				securedNow = (st.security & kWifiSecWPA2) != 0;
				if (!powerPending) radioOff = firmwareUp ? st.radio_off != 0 : YES;
				associated = st.associated != 0;
				[ssid release];
				ssid = associated ? [[NSString alloc] initWithUTF8String: st.ssid] : nil;
				rssi = st.rssi;
				[ipAddress release]; ipAddress = [ip retain];
				[router release]; router = [gw retain];
				[macAddress release];
				macAddress = [[NSString alloc] initWithFormat: @"%02x:%02x:%02x:%02x:%02x:%02x",
				              st.mac[0], st.mac[1], st.mac[2], st.mac[3], st.mac[4], st.mac[5]];
				[firmware release];
				firmware = st.fwversion[0] ? [[NSString alloc] initWithUTF8String: st.fwversion] : nil;
				[details release];
				details = associated ? [[self detailsFrom: &st] retain] : nil;
				if (associated != wasAssociated && fast) [self scan];	/* the lists swap the network over */
				if (fast && [self enabled] && [NSDate timeIntervalSinceReferenceDate] - lastScan > 15) [self scan];
			}
			[self notify];
			[ip release]; [gw release]; [mem release];
		});
		[pool release];
	});
}

/* macOS's wording and order for a connection's details */
- (NSArray *) detailsFrom: (const wifi_status *)st
{
	NSMutableArray *d = [NSMutableArray array];
#define PAIR(l, v) [d addObject: [NSArray arrayWithObjects: (l), (v), nil]]
	PAIR(@"IP Address", ipAddress ? ipAddress : @"–");
	PAIR(@"Router", router ? router : @"–");
	PAIR(@"BSSID", ([NSString stringWithFormat: @"%02x:%02x:%02x:%02x:%02x:%02x", st->bssid[0], st->bssid[1], st->bssid[2],
	                 st->bssid[3], st->bssid[4], st->bssid[5]]));
	if (st->channel)	/* the 43430 is a 2.4 GHz-only radio; channels above 14 are 5 GHz */
		PAIR(@"Channel", ([NSString stringWithFormat: @"%u (%@)", st->channel, st->channel <= 14 ? @"2.4 GHz" : @"5 GHz"]));
	PAIR(@"Security", (st->security & kWifiSecWPA2) ? @"WPA2 Personal" : @"None");
	PAIR(@"802.11 Protocol", st->ht ? @"Wi-Fi 4 (802.11n)" : @"802.11g");
	PAIR(@"RSSI", ([NSString stringWithFormat: @"%d dBm", st->rssi]));
	if (st->noise) PAIR(@"Noise", ([NSString stringWithFormat: @"%d dBm", st->noise]));
	if (st->rate_kbps) PAIR(@"Tx Rate", ([NSString stringWithFormat: @"%u Mbps", st->rate_kbps / 1000]));
#undef PAIR
	return d;
}

- (void) scan
{
	if (!available || scanning || ![self enabled]) return;
	scanning = YES;
	lastScan = [NSDate timeIntervalSinceReferenceDate];
	[self notify];
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		wifi_scan_results *res = calloc(1, sizeof *res);
		BOOL ok = res && [self connected] && [self call: kWifiMethodScan scalar: NULL count: 0 input: NULL size: 0
		                                          output: res size: sizeof *res] == KERN_SUCCESS;
		NSMutableDictionary *best = [[NSMutableDictionary alloc] init];
		uint32_t i;
		for (i = 0; ok && i < res->count && i < kWifiMaxScan; i++) {
			wifi_scan_entry *e = &res->entries[i];
			NSString *name;
			NSDictionary *have;
			if (!e->ssid[0]) continue;	/* hidden networks are not listed */
			name = [NSString stringWithUTF8String: e->ssid];
			if (!name) continue;
			have = [best objectForKey: name];
			if (have && [[have objectForKey: @"rssi"] intValue] >= e->rssi) continue;
			[best setObject: [NSDictionary dictionaryWithObjectsAndKeys: name, @"ssid",
			                  [NSNumber numberWithInt: e->rssi], @"rssi",
			                  [NSNumber numberWithInt: e->channel], @"channel",
			                  [NSNumber numberWithBool: e->security != 0], @"secure", nil] forKey: name];
		}
		free(res);
		TurinRunOnMain(^{
			NSMutableArray *list = [NSMutableArray arrayWithArray: [best allValues]];
			scanning = NO;
			if (ok && [self enabled]) {	/* a scan that finishes after Wi-Fi was turned off is dropped */
				if (ssid) {
					NSUInteger k;
					for (k = 0; k < [list count]; k++)
						if ([[[list objectAtIndex: k] objectForKey: @"ssid"] isEqual: ssid]) { [list removeObjectAtIndex: k]; break; }
				}
				[list sortUsingComparator: ^NSComparisonResult(id a, id b) {
					return [[b objectForKey: @"rssi"] compare: [a objectForKey: @"rssi"]];
				}];
				[networks release];
				networks = [list copy];
				if (autoJoin && !associated && !joining && [best objectForKey: [autoJoin objectForKey: @"ssid"]])
					[self joinName: [autoJoin objectForKey: @"ssid"] password: [autoJoin objectForKey: @"psk"]];
				[autoJoin release];
				autoJoin = nil;
			}
			[best release];
			[self notify];
		});
		[pool release];
	});
}

- (void) setEnabled: (BOOL)on
{
	BOOL needFirmware = fwState == kWifiStateProbed;	/* only a chip waiting for firmware needs `wifi up` */
	if (!available || powerPending) return;
	radioOff = !on;
	powerPending++;
	[self setMessage: nil];
	[autoJoin release];
	autoJoin = nil;
	if (!on) { [networks release]; networks = nil; }
	[self notify];
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		uint64_t arg = on;
		NSDictionary *saved;
		kern_return_t kr;
		int fd;
		if (![self connected]) { TurinRunOnMain(^{ powerPending--; [self poll]; }); [pool release]; return; }
		if (on && needFirmware) TurinRun(args(@"/usr/sbin/wifi", @"up", nil), nil, NULL);
		kr = [self call: kWifiMethodPower scalar: &arg count: 1 input: NULL size: 0 output: NULL size: 0];
		if (kr == KERN_SUCCESS) {
			if (on) unlink(WifiOff);
			else if ((fd = open(WifiOff, O_WRONLY | O_CREAT, 0644)) >= 0) close(fd);	/* the boot job keeps the radio off */
		}
		saved = [(on && kr == KERN_SUCCESS ? savedNetwork() : nil) retain];
		TurinRunOnMain(^{
			powerPending--;
			if (kr == kIOReturnNotReady) [self setMessage: @"Wi-Fi is still starting. Try again in a moment."];
			else if (kr != KERN_SUCCESS) [self setMessage: on ? @"Wi-Fi could not be turned on." : @"Wi-Fi could not be turned off."];
			if (saved && !radioOff) { [autoJoin release]; autoJoin = [saved retain]; }	/* joined once a scan sees it */
			[saved release];
			[self notify];
			[self poll];
			if (on && kr == KERN_SUCCESS) [self performSelector: @selector(scan) withObject: nil afterDelay: 0.5];
		});
		[pool release];
	});
}

- (BOOL) hasSavedPasswordFor: (NSString *)name
{
	NSDictionary *s = savedNetwork();
	return [[s objectForKey: @"ssid"] isEqual: name] && [[s objectForKey: @"psk"] length] > 0;
}

- (void) joinSaved: (NSString *)name
{
	NSDictionary *s = savedNetwork();
	if ([[s objectForKey: @"ssid"] isEqual: name]) [self joinName: name password: [s objectForKey: @"psk"]];
}

- (void) join: (NSString *)name password: (NSString *)psk { [self joinName: name password: psk ? psk : @""]; }

- (void) joinName: (NSString *)name password: (NSString *)psk
{
	NSString *n = [[name copy] autorelease], *p = [[psk copy] autorelease];
	if (!available || joining) return;
	[joining release];
	joining = [n copy];
	[self setMessage: nil];
	[self notify];
	[n retain]; [p retain];
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		wifi_join j;
		kern_return_t kr;
		memset(&j, 0, sizeof j);
		strlcpy(j.ssid, [n UTF8String], sizeof j.ssid);
		strlcpy(j.passphrase, [p UTF8String], sizeof j.passphrase);
		kr = [self connected] ? [self call: kWifiMethodJoin scalar: NULL count: 0 input: &j size: sizeof j output: NULL size: 0]
		                      : KERN_FAILURE;
		if (kr == KERN_SUCCESS) {
			saveNetwork(j.ssid, j.passphrase);
			TurinRun(args(@"/sbin/ifconfig", @"en1", @"up", nil), nil, NULL);
			TurinRun(args(@"/usr/sbin/ipconfig", @"set", @"en1", @"DHCP", nil), nil, NULL);
		}
		memset(&j, 0, sizeof j);
		TurinRunOnMain(^{
			[joining release];
			joining = nil;
			if (kr == kIOReturnNotPermitted)
				[self setMessage: [NSString stringWithFormat: @"The password for “%@” was not accepted.", n]];
			else if (kr != KERN_SUCCESS)
				[self setMessage: [NSString stringWithFormat: @"Could not join “%@”.", n]];
			[self notify];
			[self poll];
			[n release]; [p release];
		});
		[pool release];
	});
}

- (void) disconnect
{
	if (!available) return;
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if ([self connected]) [self call: kWifiMethodLeave scalar: NULL count: 0 input: NULL size: 0 output: NULL size: 0];
		TurinRun(args(@"/usr/sbin/ipconfig", @"set", @"en1", @"NONE", nil), nil, NULL);
		TurinRunOnMain(^{ [self poll]; });
		[pool release];
	});
}

- (void) forgetCurrent
{
	NSString *name = [ssid copy];
	if (!available || !name) { [name release]; return; }
	[autoJoin release];
	autoJoin = nil;
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSDictionary *saved = savedNetwork();
		if ([self connected]) [self call: kWifiMethodLeave scalar: NULL count: 0 input: NULL size: 0 output: NULL size: 0];
		if ([[saved objectForKey: @"ssid"] isEqual: name]) unlink(WifiConf);	/* only if it is still that one */
		TurinRun(args(@"/usr/sbin/ipconfig", @"set", @"en1", @"NONE", nil), nil, NULL);
		[name release];
		TurinRunOnMain(^{ [self poll]; });
		[pool release];
	});
}

@end

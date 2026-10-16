#import "TurinNetworkPane.h"
#import "TurinUtil.h"
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

enum { ListW = 180, IfRowH = 44 };

/* ---- reading the state (on the queue) ---- */

static NSString *
displayName(NSString *ifname)
{
	if ([ifname isEqual: @"en0"]) return @"Ethernet";
	if ([ifname isEqual: @"en1"]) return @"Wi-Fi";
	if ([ifname hasPrefix: @"lo"]) return @"Loopback";
	if ([ifname hasPrefix: @"bridge"]) return @"Bridge";
	if ([ifname hasPrefix: @"en"]) return [NSString stringWithFormat: @"Ethernet (%@)", ifname];
	return ifname;
}

static NSString *
addr(const struct sockaddr *sa)
{
	char buf[INET6_ADDRSTRLEN];
	if (!sa) return nil;
	if (sa->sa_family == AF_INET && inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, buf, sizeof buf))
		return [NSString stringWithUTF8String: buf];
	if (sa->sa_family == AF_INET6 && inet_ntop(AF_INET6, &((const struct sockaddr_in6 *)sa)->sin6_addr, buf, sizeof buf))
		return [NSString stringWithUTF8String: buf];
	return nil;
}

static NSString *
bytes(unsigned long long n)
{
	if (n < 1024) return [NSString stringWithFormat: @"%llu bytes", n];
	if (n < 1024 * 1024) return [NSString stringWithFormat: @"%.1f KB", n / 1024.0];
	if (n < 1024ULL * 1024 * 1024) return [NSString stringWithFormat: @"%.1f MB", n / (1024.0 * 1024)];
	return [NSString stringWithFormat: @"%.2f GB", n / (1024.0 * 1024 * 1024)];
}

static NSArray *
cmd(NSString *a, NSString *b, NSString *c, NSString *d)
{
	return [NSArray arrayWithObjects: a, b, c, d, nil];
}

/* one dictionary per interface: name, display, up, running, ipv4, netmask, broadcast, ipv6 (array), mac, rx, tx, mtu,
 * router, dhcp; sorted Ethernet, Wi-Fi, others, loopback */
static NSArray *
gather(void)
{
	struct ifaddrs *ifs, *i;
	NSMutableDictionary *by = [NSMutableDictionary dictionary];
	NSMutableArray *order = [NSMutableArray array], *out = [NSMutableArray array];
	NSString *name;
	if (getifaddrs(&ifs) != 0) return out;
	for (i = ifs; i; i = i->ifa_next) {
		NSMutableDictionary *d;
		name = [NSString stringWithUTF8String: i->ifa_name];
		/* tunnels and pseudo-interfaces have nothing to show */
		if ([name hasPrefix: @"gif"] || [name hasPrefix: @"stf"] || [name hasPrefix: @"utun"] || [name hasPrefix: @"awdl"]) continue;
		if (!(d = [by objectForKey: name])) {
			d = [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", displayName(name), @"display",
			     [NSMutableArray array], @"ipv6", nil];
			[by setObject: d forKey: name];
			[order addObject: name];
		}
		[d setObject: [NSNumber numberWithBool: (i->ifa_flags & IFF_UP) != 0] forKey: @"up"];
		[d setObject: [NSNumber numberWithBool: (i->ifa_flags & IFF_RUNNING) != 0] forKey: @"running"];
		if (!i->ifa_addr) continue;
		switch (i->ifa_addr->sa_family) {
		case AF_INET:
			if (![d objectForKey: @"ipv4"]) {
				if (addr(i->ifa_addr)) [d setObject: addr(i->ifa_addr) forKey: @"ipv4"];
				if (addr(i->ifa_netmask)) [d setObject: addr(i->ifa_netmask) forKey: @"netmask"];
				if ((i->ifa_flags & IFF_BROADCAST) && addr(i->ifa_broadaddr)) [d setObject: addr(i->ifa_broadaddr) forKey: @"broadcast"];
			}
			break;
		case AF_INET6:
			if (addr(i->ifa_addr)) [[d objectForKey: @"ipv6"] addObject: addr(i->ifa_addr)];
			break;
		case AF_LINK: {
			const struct sockaddr_dl *dl = (const struct sockaddr_dl *)i->ifa_addr;
			const struct if_data *data = i->ifa_data;
			if (dl->sdl_alen == 6) {
				const unsigned char *m = (const unsigned char *)LLADDR(dl);
				[d setObject: [NSString stringWithFormat: @"%02x:%02x:%02x:%02x:%02x:%02x", m[0], m[1], m[2], m[3], m[4], m[5]]
				      forKey: @"mac"];
			}
			if (data) {
				[d setObject: [NSNumber numberWithUnsignedLongLong: data->ifi_ibytes] forKey: @"rx"];
				[d setObject: [NSNumber numberWithUnsignedLongLong: data->ifi_obytes] forKey: @"tx"];
				[d setObject: [NSNumber numberWithUnsignedLongLong: data->ifi_ipackets] forKey: @"rxp"];
				[d setObject: [NSNumber numberWithUnsignedLongLong: data->ifi_opackets] forKey: @"txp"];
				[d setObject: [NSNumber numberWithUnsignedInt: data->ifi_mtu] forKey: @"mtu"];
			}
			break;
		}
		}
	}
	freeifaddrs(ifs);
	for (name in order) {
		NSMutableDictionary *d = [by objectForKey: name];
		if ([d objectForKey: @"ipv4"] && ![name hasPrefix: @"lo"]) {
			NSString *r = TurinToolLine(cmd(@"/usr/sbin/ipconfig", @"getoption", name, @"router"));
			if (r) [d setObject: r forKey: @"router"];
			/* a lease IPConfiguration holds means DHCP (getpacket prints it); otherwise the address was set by hand */
			[d setObject: [NSNumber numberWithBool: TurinToolLine(cmd(@"/usr/sbin/ipconfig", @"getpacket", name, nil)) != nil]
			      forKey: @"dhcp"];
		}
	}
	[order sortUsingComparator: ^NSComparisonResult(id a, id b) {
		int ra = [a isEqual: @"en0"] ? 0 : [a isEqual: @"en1"] ? 1 : [a hasPrefix: @"lo"] ? 3 : 2;
		int rb = [b isEqual: @"en0"] ? 0 : [b isEqual: @"en1"] ? 1 : [b hasPrefix: @"lo"] ? 3 : 2;
		return ra != rb ? (ra < rb ? NSOrderedAscending : NSOrderedDescending) : [a compare: b];
	}];
	for (name in order) [out addObject: [by objectForKey: name]];
	return out;
}

/* /etc/resolv.conf: nameserver and search/domain lines */
static void
readResolver(NSMutableArray *servers, NSMutableArray *domains)
{
	NSString *s = [NSString stringWithContentsOfFile: @"/etc/resolv.conf" encoding: NSUTF8StringEncoding error: NULL], *line;
	for (line in [s componentsSeparatedByString: @"\n"]) {
		NSArray *w = [[line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]]
		                 componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
		NSString *k = [w count] ? [w objectAtIndex: 0] : nil;
		NSUInteger j;
		if ([k isEqual: @"nameserver"] && [w count] > 1) [servers addObject: [w objectAtIndex: 1]];
		else if ([k isEqual: @"search"] || [k isEqual: @"domain"])
			for (j = 1; j < [w count]; j++) if ([[w objectAtIndex: j] length]) [domains addObject: [w objectAtIndex: j]];
	}
}

typedef enum { StateConnected, StateSelfAssigned, StateDisconnected, StateInactive } IfState;

static IfState
stateOf(NSDictionary *d)
{
	NSString *v4 = [d objectForKey: @"ipv4"];
	if (![[d objectForKey: @"up"] boolValue]) return StateInactive;
	if (![[d objectForKey: @"running"] boolValue] || !v4) return StateDisconnected;
	if ([v4 hasPrefix: @"169.254."]) return StateSelfAssigned;
	return StateConnected;
}

static NSString *
stateText(IfState s)
{
	switch (s) {
	case StateConnected: return @"Connected";
	case StateSelfAssigned: return @"Self-assigned IP";
	case StateDisconnected: return @"Not connected";
	default: return @"Inactive";
	}
}

static NSColor *
stateColor(IfState s)
{
	switch (s) {
	case StateConnected: return [NSColor colorWithCalibratedRed: 0.20 green: 0.75 blue: 0.30 alpha: 1];
	case StateSelfAssigned: return [NSColor colorWithCalibratedRed: 0.98 green: 0.70 blue: 0.15 alpha: 1];
	case StateDisconnected: return [NSColor colorWithCalibratedRed: 0.92 green: 0.28 blue: 0.25 alpha: 1];
	default: return [NSColor colorWithCalibratedWhite: 0.65 alpha: 1];
	}
}

/* ---- the interface list ---- */

@interface TurinIfList : NSView { TurinNetworkPane *pane; }
- (id) initWithFrame: (NSRect)f pane: (TurinNetworkPane *)p;
@end

@implementation TurinIfList

- (id) initWithFrame: (NSRect)f pane: (TurinNetworkPane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }
- (BOOL) acceptsFirstMouse: (NSEvent *)e { return YES; }
- (NSRect) rowRect: (NSUInteger)i { return NSMakeRect(6, NSHeight([self bounds]) - 6 - (i + 1) * IfRowH, NSWidth([self bounds]) - 12, IfRowH - 2); }

- (void) drawRect: (NSRect)dirty
{
	NSArray *ifs = [pane interfaces];
	NSUInteger i;
	for (i = 0; i < [ifs count]; i++) {
		NSDictionary *d = [ifs objectAtIndex: i];
		NSRect r = [self rowRect: i];
		BOOL sel = (NSInteger)i == [pane selected];
		IfState st = stateOf(d);
		NSColor *ink = sel ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0.08 alpha: 1];
		NSDictionary *na = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 13], NSFontAttributeName, ink,
		                    NSForegroundColorAttributeName, nil];
		NSDictionary *sa = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 10], NSFontAttributeName,
		                    sel ? [NSColor colorWithCalibratedWhite: 1 alpha: 0.85] : [NSColor colorWithCalibratedWhite: 0 alpha: 0.5],
		                    NSForegroundColorAttributeName, nil];
		if (sel) {
			[TurinAccent() set];
			[[NSBezierPath bezierPathWithRoundedRect: r xRadius: 6 yRadius: 6] fill];
		}
		TurinDrawIcon([[d objectForKey: @"name"] isEqual: @"en1"] ? TurinIconWifi : TurinIconNetwork,
		              NSMakeRect(NSMinX(r) + 6, NSMidY(r) - 14, 28, 28));
		[[d objectForKey: @"display"] drawAtPoint: NSMakePoint(NSMinX(r) + 42, NSMidY(r) + 1) withAttributes: na];
		[stateColor(st) set];
		[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(NSMinX(r) + 42, NSMidY(r) - 12, 8, 8)] fill];
		[stateText(st) drawAtPoint: NSMakePoint(NSMinX(r) + 54, NSMidY(r) - 15) withAttributes: sa];
	}
}

- (void) mouseDown: (NSEvent *)e
{
	NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
	NSUInteger i;
	for (i = 0; i < [[pane interfaces] count]; i++)
		if (NSPointInRect(p, [self rowRect: i])) { [pane select: i]; return; }
}

@end

/* ---- the details of the chosen interface ---- */

@interface TurinIfDetail : NSView { TurinNetworkPane *pane; }
- (id) initWithFrame: (NSRect)f pane: (TurinNetworkPane *)p;
@end

@implementation TurinIfDetail

- (id) initWithFrame: (NSRect)f pane: (TurinNetworkPane *)p { if ((self = [super initWithFrame: f])) pane = p; return self; }
- (BOOL) isFlipped { return NO; }

- (void) drawRect: (NSRect)dirty
{
	NSArray *ifs = [pane interfaces];
	NSDictionary *d = [pane selected] >= 0 && [pane selected] < (NSInteger)[ifs count] ? [ifs objectAtIndex: [pane selected]] : nil;
	NSDictionary *ta = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 15], NSFontAttributeName,
	                    [NSColor blackColor], NSForegroundColorAttributeName, nil];
	NSDictionary *la = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 11], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0 alpha: 0.5], NSForegroundColorAttributeName, nil];
	NSDictionary *va = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont systemFontOfSize: 12], NSFontAttributeName,
	                    [NSColor colorWithCalibratedWhite: 0.08 alpha: 1], NSForegroundColorAttributeName, nil];
	NSMutableArray *rows = [NSMutableArray array];
	CGFloat y = NSHeight([self bounds]) - 30;
	IfState st;
	NSArray *pair;
	if (!d) {
		[@"No network interfaces." drawAtPoint: NSMakePoint(16, y) withAttributes: la];
		return;
	}
	st = stateOf(d);
	[[d objectForKey: @"display"] drawAtPoint: NSMakePoint(16, y) withAttributes: ta];
	[stateColor(st) set];
	[[NSBezierPath bezierPathWithOvalInRect: NSMakeRect(16, y - 17, 9, 9)] fill];
	[stateText(st) drawAtPoint: NSMakePoint(30, y - 21) withAttributes: va];
	y -= 52;
#define ROW(l, v) do { id _v = (v); if (_v) [rows addObject: [NSArray arrayWithObjects: (l), _v, nil]]; } while (0)
	ROW(@"Interface", [d objectForKey: @"name"]);
	if ([d objectForKey: @"ipv4"]) {
		ROW(@"Configure IPv4", [[d objectForKey: @"dhcp"] boolValue] ? @"Using DHCP" : @"Manually");
		ROW(@"IP Address", [d objectForKey: @"ipv4"]);
		ROW(@"Subnet Mask", [d objectForKey: @"netmask"]);
		ROW(@"Router", [d objectForKey: @"router"] ? [d objectForKey: @"router"] : @"–");
		if (![[d objectForKey: @"name"] hasPrefix: @"lo"])
			ROW(@"DNS Servers", [[pane dns] count] ? [[pane dns] componentsJoinedByString: @", "] : @"–");
		if ([[pane searchDomains] count] && ![[d objectForKey: @"name"] hasPrefix: @"lo"])
			ROW(@"Search Domains", [[pane searchDomains] componentsJoinedByString: @", "]);
	}
	if ([[d objectForKey: @"ipv6"] count]) {
		NSString *a;
		BOOL first = YES;
		for (a in [d objectForKey: @"ipv6"]) { ROW(first ? @"IPv6 Address" : @"", a); first = NO; }
	}
	ROW(@"Hardware (MAC)", [d objectForKey: @"mac"]);
	if ([d objectForKey: @"mtu"]) ROW(@"MTU", [[d objectForKey: @"mtu"] stringValue]);
	if ([d objectForKey: @"rx"])
		ROW(@"Received", ([NSString stringWithFormat: @"%@ (%@ packets)", bytes([[d objectForKey: @"rx"] unsignedLongLongValue]),
		                  [d objectForKey: @"rxp"]]));
	if ([d objectForKey: @"tx"])
		ROW(@"Sent", ([NSString stringWithFormat: @"%@ (%@ packets)", bytes([[d objectForKey: @"tx"] unsignedLongLongValue]),
		              [d objectForKey: @"txp"]]));
	ROW(@"Computer Name", [pane hostname]);
#undef ROW
	for (pair in rows) {
		NSString *l = [pair objectAtIndex: 0];
		NSSize sz = [l sizeWithAttributes: la];
		if ([l length]) [l drawAtPoint: NSMakePoint(130 - sz.width, y + 1) withAttributes: la];
		[[pair objectAtIndex: 1] drawInRect: NSMakeRect(140, y - 2, NSWidth([self bounds]) - 150, 18) withAttributes: va];
		y -= 22;
		if (y < 6) break;
	}
}

@end

/* ---- the pane ---- */

@implementation TurinNetworkPane

- (NSString *) title { return @"Network"; }
- (TurinIconKind) icon { return TurinIconNetwork; }
- (NSArray *) interfaces { return interfaces; }
- (NSInteger) selected { return selected; }
- (NSString *) hostname { return hostname; }
- (NSArray *) dns { return dns; }
- (NSArray *) searchDomains { return searchDomains; }

- (id) init
{
	if ((self = [super init])) {
		queue = dispatch_queue_create("turin.network", NULL);
		interfaces = [[NSArray alloc] init];
	}
	return self;
}

- (void) dealloc
{
	[interfaces release]; [hostname release]; [dns release]; [searchDomains release];
	[listView release]; [detailView release];
	[super dealloc];
}

- (void) loadView: (NSView *)v
{
	const CGFloat W = TurinPaneWidth;
	[(TurinGroupView *)v setGroups: [NSArray arrayWithObjects:
	    [NSValue valueWithRect: NSMakeRect(20, 16, ListW, 484)],
	    [NSValue valueWithRect: NSMakeRect(20 + ListW + 12, 16, W - 52 - ListW, 484)], nil]];
	listView = [[TurinIfList alloc] initWithFrame: NSMakeRect(20, 16, ListW, 484) pane: self];
	detailView = [[TurinIfDetail alloc] initWithFrame: NSMakeRect(20 + ListW + 12, 16, W - 52 - ListW, 484) pane: self];
	[v addSubview: listView];
	[v addSubview: detailView];
}

- (void) select: (NSInteger)i
{
	selected = i;
	[listView setNeedsDisplay: YES];
	[detailView setNeedsDisplay: YES];
}

- (void) refresh
{
	if (gathering) return;
	gathering = YES;
	dispatch_async(queue, ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSArray *ifs = [gather() retain];
		NSMutableArray *servers = [[NSMutableArray alloc] init], *domains = [[NSMutableArray alloc] init];
		char host[256] = "";
		NSString *h;
		readResolver(servers, domains);
		gethostname(host, sizeof host);
		h = [[NSString alloc] initWithUTF8String: host];
		TurinRunOnMain(^{
			NSString *was = selected >= 0 && selected < (NSInteger)[interfaces count]
			              ? [[[interfaces objectAtIndex: selected] objectForKey: @"name"] retain] : nil;
			NSUInteger k;
			gathering = NO;
			[interfaces release]; interfaces = ifs;
			[dns release]; dns = servers;
			[searchDomains release]; searchDomains = domains;
			[hostname release]; hostname = h;
			/* keep the same interface chosen across refreshes; the first connected one on the first */
			selected = -1;
			for (k = 0; was && k < [interfaces count]; k++)
				if ([[[interfaces objectAtIndex: k] objectForKey: @"name"] isEqual: was]) selected = k;
			for (k = 0; selected < 0 && k < [interfaces count]; k++)
				if (stateOf([interfaces objectAtIndex: k]) == StateConnected) selected = k;
			if (selected < 0 && [interfaces count]) selected = 0;
			[was release];
			[listView setNeedsDisplay: YES];
			[detailView setNeedsDisplay: YES];
		});
		[pool release];
	});
}

- (void) didShow
{
	if (!timer) {
		timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_source_set_event_handler(timer, ^{ TurinRunOnMain(^{ [self refresh]; }); });
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC, NSEC_PER_SEC);
		dispatch_resume(timer);
	}
}

- (void) didHide
{
	if (timer) { dispatch_source_cancel(timer); dispatch_release(timer); timer = NULL; }
}

@end

/* Renders icons/Turin.png: a gear on a rounded graphite tile, in the style of the sidebar's icons (TurinIcons.m).
 * Host tool, run once:  clang -fobjc-arc -framework AppKit tools/make_icon.m -o /tmp/make_icon && /tmp/make_icon
 * then:                 sips -s format tiff icons/Turin.png --out icons/Turin.tiff */
#import <AppKit/AppKit.h>
#include <math.h>

int
main(void)
{
	@autoreleasepool {
		NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 256 pixelsHigh: 256 bitsPerSample: 8
		    samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 32];
		NSRect tile = NSMakeRect(8, 8, 240, 240);
		NSPoint c = NSMakePoint(128, 128);
		NSBezierPath *gear = [NSBezierPath bezierPath];
		int i, teeth = 12;
		[NSGraphicsContext saveGraphicsState];
		[NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
		[[NSColor clearColor] set];
		NSRectFillUsingOperation(NSMakeRect(0, 0, 256, 256), NSCompositingOperationClear);
		[[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedRed: 0.62 green: 0.66 blue: 0.72 alpha: 1]
		                               endingColor: [NSColor colorWithCalibratedRed: 0.30 green: 0.33 blue: 0.39 alpha: 1]]
		    drawInBezierPath: [NSBezierPath bezierPathWithRoundedRect: tile xRadius: 52 yRadius: 52] angle: -90];
		/* the gear: a toothed rim around a hole */
		for (i = 0; i < teeth * 4; i++) {
			double a = i * M_PI * 2 / (teeth * 4) + M_PI / (teeth * 4);
			double r = (i % 4 == 0 || i % 4 == 1) ? 92 : 74;
			NSPoint p = NSMakePoint(c.x + cos(a) * r, c.y + sin(a) * r);
			if (i == 0) [gear moveToPoint: p]; else [gear lineToPoint: p];
		}
		[gear closePath];
		[gear appendBezierPathWithOvalInRect: NSMakeRect(c.x - 34, c.y - 34, 68, 68)];
		[gear setWindingRule: NSWindingRuleEvenOdd];
		[[NSColor colorWithCalibratedWhite: 0 alpha: 0.25] set];
		{
			NSAffineTransform *t = [NSAffineTransform transform];
			[t translateXBy: 0 yBy: -4];
			[[t transformBezierPath: gear] fill];
		}
		[[[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedWhite: 1 alpha: 1]
		                               endingColor: [NSColor colorWithCalibratedWhite: 0.82 alpha: 1]] drawInBezierPath: gear angle: -90];
		[NSGraphicsContext restoreGraphicsState];
		[[rep representationUsingType: NSBitmapImageFileTypePNG properties: @{}] writeToFile: @"icons/Turin.png" atomically: YES];
	}
	return 0;
}

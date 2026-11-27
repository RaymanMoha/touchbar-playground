#import "TouchBarBridge.h"

// System-wide Touch Bar presentation is private AppKit API. Keep it isolated,
// check availability, and leave Apple's Control Strip and physical Esc alone.
@interface NSTouchBar (PlaygroundPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

BOOL PlaygroundPresent(NSTouchBar *bar) {
    @try {
        if (![NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)]) return NO;
        [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:nil];
        return YES;
    } @catch (NSException *e) { NSLog(@"Touch Bar presentation: %@", e.reason); return NO; }
}
void PlaygroundDismiss(NSTouchBar *bar) {
    @try {
        if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)])
            [NSTouchBar dismissSystemModalTouchBar:bar];
    } @catch (NSException *e) { NSLog(@"Touch Bar dismissal: %@", e.reason); }
}

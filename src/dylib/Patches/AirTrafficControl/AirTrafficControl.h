// Air Traffic Control: opens each routed site in the profile chosen for it, like Arc's, wherever the link comes from.
#import "StdPatch/StdPatch.h"

extern DPPatch DPAirTrafficControl, DPAirTrafficInsideDia;

// Routes.m: saved in com.diapatches as airTrafficRoutes, [{url, match, profile}], and airTrafficDefault, a profile ID or ""
// for whichever profile is in front.
static NSString *const DPMatchContains = @"contains", *const DPMatchEquals = @"equals";
NSArray<NSDictionary *> *DPRoutes(void);
void DPSetRoutes(NSArray<NSDictionary *> *routes);
NSString *DPDefaultProfile(void);
void DPSetDefaultProfile(NSString *profileID);
NSString *DPRouteURL(NSString *text);    // What was typed, tidied: "https://www.example.com/x " is "example.com/x".
NSString *DPRoutedProfile(NSURL *url);  // The profile the first matching route sends `url` to, or nil.

@interface NSObject (DPAirSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;  // AXCoreUtilities: reads Swift properties the Obj-C runtime hides.
@end

// Profiles.m: Dia's profiles, read from the switcher in each window, the sidebar's or the dots in the tab strip.
NSArray<NSDictionary *> *DPProfiles(void);    // {id, name}, left to right.
NSMenuItem *DPProfileMenuItem(NSUInteger index);  // The Window menu's item for the profile at `index` in DPProfiles().
NSView *DPSwitcherIn(NSWindow *window);
NSDictionary *DPSwitcherItems(NSView *switcher);  // Swift SpaceID → the item view for it.
NSString *DPWindowProfile(NSWindow *window);  // The profile a browser window shows, or nil for any other window.
NSWindow *DPWindowOnProfile(NSString *profileID);

void DPSwitchToProfile(NSWindow *window, NSString *profileID, void (^done)(BOOL switched));  // Switch.m

// Routing.m: where a link goes, and how it gets there.
BOOL DPRoutingReady(void);  // On, with at least two profiles to route between.
NSString *DPDestination(NSURL *url, NSURL *from, BOOL external);  // The profile to open `url` in, or nil to leave it to Dia.
void DPOpenInProfile(NSURL *url, NSString *profileID);
void DPForgetOld(NSMutableDictionary<NSString *, NSDate *> *times, NSTimeInterval seconds);  // Drops times that long ago.
void DPTrace(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);  // Logs with the developer tools on: log stream --predicate 'eventMessage CONTAINS "DiaPatches ATC"'

// Hooks.m: the hooks that catch links wherever they come from.
void DPInstallRouting(void);
NSString *DPVerifyRouting(DPPatch *patch);

// Redirects.m: a load that's redirected to a routed site, caught when the page commits to it.
void DPInstallRedirects(void);
void DPNoteFromOutside(NSURL *url);  // A link from another app, so its redirect routes like the link would.
void DPNoteLoad(id page, NSURL *url, NSURL *before);  // A load let through, from `before` (nil for a new tab), to watch.

// Picker.m: the pieces of its Settings page, and the page's rows: the Routes group (Editor.m) and the Default group.
NSTextField *DPNote(NSString *text);
NSPopUpButton *DPProfilePicker(NSString *first, NSString *chosen, id target, SEL action);  // The profiles, after `first` if given.
NSArray<NSView *> *DPAirTrafficRows(void);

@interface DPRoutesView : NSStackView <NSTextFieldDelegate>  // Editor.m
@end

@interface DPDefaultRow : NSStackView  // Picker.m
@end

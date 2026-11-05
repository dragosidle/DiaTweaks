// Air Traffic Control: opens each routed site in the profile chosen for it, like Arc's, wherever the link comes from.
#import "StdPatch/StdPatch.h"

extern DPPatch DPAirTrafficControl, DPAirTrafficInsideDia;

// Routes.m: saved in com.diapatches as airTrafficRoutes, [{domain, profile}], and airTrafficDefault, a profile ID or "" for
// whichever profile is in front.
NSArray<NSDictionary *> *DPRoutes(void);
void DPSetRoutes(NSArray<NSDictionary *> *routes);
NSString *DPDefaultProfile(void);
void DPSetDefaultProfile(NSString *profileID);
NSString *DPRouteDomain(NSString *text);  // What was typed, as a host: "https://www.Example.com/x" is "example.com".
NSString *DPRoutedProfile(NSURL *url);    // The profile a route sends `url` to, or nil. A route covers its subdomains.

// Profiles.m: Dia's profiles, read from the switcher in each window, the sidebar's or the dots in the tab strip.
NSArray<NSDictionary *> *DPProfiles(void);    // {id, name}, left to right.
NSString *DPWindowProfile(NSWindow *window);  // The profile a browser window shows, or nil for any other window.
NSWindow *DPWindowOnProfile(NSString *profileID);
void DPSwitchToProfile(NSWindow *window, NSString *profileID, void (^done)(BOOL switched));

// Routing.m: where a link goes, and how it gets there.
BOOL DPRoutingReady(void);  // On, with at least two profiles to route between.
NSString *DPDestination(NSURL *url, NSURL *from, BOOL external);  // The profile to open `url` in, or nil to leave it to Dia.
void DPOpenInProfile(NSURL *url, NSString *profileID);
void DPTrace(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);  // Logs with the developer tools on: log stream --predicate 'eventMessage CONTAINS "DiaPatches ATC"'

// Hooks.m: the hooks that catch links wherever they come from.
void DPInstallRouting(void);
NSString *DPVerifyRouting(DPPatch *patch);

// Picker.m: the pieces of its Settings page, and the page's rows: the Routes group (Editor.m) and the Default group.
NSTextField *DPNote(NSString *text);
NSPopUpButton *DPProfilePicker(NSString *first, NSString *chosen, id target, SEL action);  // The profiles, after `first` if given.
NSArray<NSView *> *DPAirTrafficRows(void);

@interface DPRoutesView : NSStackView <NSTextFieldDelegate>  // Editor.m
@end

@interface DPDefaultRow : NSStackView  // Picker.m
@end

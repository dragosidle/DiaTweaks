// The pieces the Settings page is built from, and its Default group, for links from other apps that no route covers.
#import "Patches/AirTrafficControl/AirTrafficControl.h"

NSTextField *DPNote(NSString *text) {
    NSTextField *note = [NSTextField wrappingLabelWithString:text];
    note.font = [NSFont systemFontOfSize:13];
    note.textColor = NSColor.secondaryLabelColor;
    [note setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return note;
}

static NSString *DPProfileTitle(NSDictionary *profile) {
    NSString *emoji = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] dictionaryForKey:@"profileEmojis"][profile[@"id"]];
    return emoji.length ? [NSString stringWithFormat:@"%@ %@", emoji, profile[@"name"]] : profile[@"name"];
}

// A menu of the profiles, after `first` if there is one, with `chosen` selected. A chosen profile that's gone shows as missing.
NSPopUpButton *DPProfilePicker(NSString *first, NSString *chosen, id target, SEL action) {
    NSPopUpButton *picker = [NSPopUpButton new];
    picker.controlSize = NSControlSizeSmall;
    picker.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    if (first) [picker.menu addItemWithTitle:first action:NULL keyEquivalent:@""].representedObject = @"";
    for (NSDictionary *profile in DPProfiles())
        [picker.menu addItemWithTitle:DPProfileTitle(profile) action:NULL keyEquivalent:@""].representedObject = profile[@"id"];
    NSInteger index = [picker indexOfItemWithRepresentedObject:chosen ?: @""];
    if (index < 0) {
        [picker.menu addItemWithTitle:@"Missing profile" action:NULL keyEquivalent:@""].enabled = NO;
        index = picker.numberOfItems - 1;
    }
    [picker selectItemAtIndex:index];
    picker.target = target;
    picker.action = action;
    picker.enabled = DPAirTrafficControl.on;
    return picker;
}

@implementation DPDefaultRow
- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.spacing = 12;
    self.identifier = @"Default";
    [self reload];
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self reload];
}

- (void)reload {
    for (NSView *view in self.arrangedSubviews.copy) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self addArrangedSubview:DPNote(@"Links from other apps with no route open in")];
    [self addArrangedSubview:DPProfilePicker(@"The Front Profile", DPDefaultProfile(), self, @selector(pick:))];
}

- (void)pick:(NSPopUpButton *)picker { DPSetDefaultProfile(picker.selectedItem.representedObject); }
@end

NSArray<NSView *> *DPAirTrafficRows(void) { return @[ [DPRoutesView new], [DPDefaultRow new] ]; }

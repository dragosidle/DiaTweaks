// The Routes group on the Settings page: a New Route button and a row per route, saved as they change.
#import "Patches/AirTrafficControl/AirTrafficControl.h"

@implementation DPRoutesView
- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.spacing = 8;
    self.identifier = @"Routes";
    [self reload];
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self reload];  // Profiles may have come or gone since the page was built.
}

- (void)addRow:(NSView *)row {
    [self addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
}

- (NSView *)rowForRoute:(NSDictionary *)route at:(NSUInteger)index {
    NSTextField *domain = [NSTextField textFieldWithString:route[@"domain"]];
    domain.placeholderString = @"example.com";
    domain.controlSize = NSControlSizeSmall;
    domain.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    domain.delegate = self;
    domain.tag = index;
    domain.enabled = DPAirTrafficControl.on;
    [domain.widthAnchor constraintEqualToConstant:180].active = YES;
    NSPopUpButton *picker = DPProfilePicker(nil, route[@"profile"], self, @selector(pick:));
    picker.tag = index;
    NSButton *remove = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"minus.circle.fill" accessibilityDescription:@"Remove Route"]
                                          target:self action:@selector(remove:)];
    remove.bordered = NO;
    remove.contentTintColor = NSColor.secondaryLabelColor;
    remove.tag = index;
    remove.enabled = DPAirTrafficControl.on;
    NSStackView *row = [NSStackView stackViewWithViews:@[ domain, DPNote(@"opens in"), picker, remove ]];
    row.spacing = 8;
    [row setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

- (void)reload {
    for (NSView *view in self.arrangedSubviews.copy) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    BOOL ready = DPProfiles().count >= 2;
    NSTextField *lead = DPNote(ready ? @"A routed site opens in its profile wherever its link is clicked, switching to it if it has to. "
                                        "A route for example.com covers its subdomains too."
                                     : @"Air Traffic Control needs two or more profiles. Add them in Settings › Profiles.");
    NSButton *add = [NSButton buttonWithTitle:@"New Route" target:self action:@selector(add)];
    add.controlSize = NSControlSizeSmall;
    add.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    add.hidden = !ready;
    add.enabled = DPAirTrafficControl.on;
    NSStackView *head = [NSStackView stackViewWithViews:@[ lead, add ]];
    head.spacing = 12;
    head.alignment = NSLayoutAttributeCenterY;
    [self addRow:head];
    if (!ready) return;
    [DPRoutes() enumerateObjectsUsingBlock:^(NSDictionary *route, NSUInteger index, BOOL *_) {
        NSBox *line = [NSBox new];
        line.boxType = NSBoxSeparator;
        [self addRow:line];
        [self addRow:[self rowForRoute:route at:index]];
    }];
}

- (void)add {
    DPSetRoutes([DPRoutes() arrayByAddingObject:@{ @"domain" : @"", @"profile" : DPProfiles().firstObject[@"id"] ?: @"" }]);
    [self reload];
    NSView *last = self.arrangedSubviews.lastObject;
    [self.window makeFirstResponder:[last isKindOfClass:NSStackView.class] ? ((NSStackView *)last).arrangedSubviews.firstObject : nil];
}

- (void)change:(NSUInteger)index with:(void (^)(NSMutableDictionary *route))change {
    NSMutableArray<NSDictionary *> *routes = [DPRoutes() mutableCopy];
    if (index >= routes.count) return;
    NSMutableDictionary *route = [routes[index] mutableCopy];
    change(route);
    routes[index] = route;
    DPSetRoutes(routes);
}

// Saved as typed, so nothing is lost when the window closes, and tidied into a host once editing ends.
- (void)controlTextDidChange:(NSNotification *)note {
    NSTextField *field = note.object;
    [self change:field.tag with:^(NSMutableDictionary *route) { route[@"domain"] = field.stringValue; }];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    NSTextField *field = note.object;
    NSString *domain = DPRouteDomain(field.stringValue);
    field.stringValue = domain;
    [self change:field.tag with:^(NSMutableDictionary *route) { route[@"domain"] = domain; }];
}

- (void)pick:(NSPopUpButton *)picker {
    NSString *profileID = picker.selectedItem.representedObject;
    if (profileID.length) [self change:picker.tag with:^(NSMutableDictionary *route) { route[@"profile"] = profileID; }];
}

- (void)remove:(NSButton *)button {
    NSMutableArray<NSDictionary *> *routes = [DPRoutes() mutableCopy];
    if ((NSUInteger)button.tag < routes.count) [routes removeObjectAtIndex:button.tag];
    DPSetRoutes(routes);
    [self reload];
}
@end

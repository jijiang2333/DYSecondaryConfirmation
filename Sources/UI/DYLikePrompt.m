#import "DYLikePrompt.h"

static __weak DYLikePrompt *DYLikeVisiblePrompt;

@interface DYLikePrompt ()
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIStackView *buttons;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, copy) void (^decision)(BOOL);
@property(nonatomic) BOOL finishing;
@end

@implementation DYLikePrompt

+ (void)presentForAction:(DYLikeActionType)action intent:(DYLikeIntent)intent
                    name:(NSString *)name isComment:(BOOL)isComment
                decision:(void (^)(BOOL))decision {
    NSAssert(NSThread.isMainThread, @"Present confirmations on the main thread");
    UIWindow *window = DYLikeActiveWindow();
    if (!window || DYLikeVisiblePrompt) {
        if (decision) decision(NO);
        return;
    }
    DYLikePrompt *prompt = [[self alloc] initWithFrame:window.bounds];
    prompt.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    prompt.overrideUserInterfaceStyle = DYLikeUserInterfaceStyle();
    prompt.decision = decision;
    DYLikeVisiblePrompt = prompt;
    [window addSubview:prompt];
    [prompt configureAction:action intent:intent name:name isComment:isComment];
    [NSNotificationCenter.defaultCenter addObserver:prompt selector:@selector(cancel)
        name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:prompt selector:@selector(updateTheme)
        name:DYLikeThemeDidChangeNotification object:nil];
    [prompt layoutIfNeeded];
    prompt.alpha = 0;
    prompt.panel.transform = UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.97, 0.97);
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.18 animations:^{
        prompt.alpha = 1;
        prompt.panel.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        if (!prompt.finishing) UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, prompt.heading);
    }];
}

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] maximumPointSize:30];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title primary:(BOOL)primary accent:(UIColor *)accent {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] maximumPointSize:24];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.8;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 10, 14, 10);
    button.layer.cornerRadius = 8;
    button.backgroundColor = primary ? accent : UIColor.tertiarySystemFillColor;
    [button setTitleColor:primary ? UIColor.whiteColor : UIColor.labelColor forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    [button addTarget:self action:primary ? @selector(confirm) : @selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)configureAction:(DYLikeActionType)action intent:(DYLikeIntent)intent name:(NSString *)name isComment:(BOOL)isComment {
    self.accessibilityViewIsModal = YES;
    UIControl *scrim = [[UIControl alloc] initWithFrame:self.bounds];
    scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.46];
    scrim.isAccessibilityElement = NO;
    [scrim addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:scrim];

    NSString *verb = action == DYLikeActionLike ? @"点赞" : action == DYLikeActionFavorite ? @"收藏" : @"关注";
    NSString *symbol = action == DYLikeActionLike ? @"heart.fill" : action == DYLikeActionFavorite ? @"bookmark.fill" : @"person.badge.plus";
    NSString *object = action == DYLikeActionFollow ? @"这位用户" : isComment ? @"这条评论" : @"当前内容";
    NSString *title = [NSString stringWithFormat:@"确认%@%@？", verb, object];
    NSString *message = action == DYLikeActionLike ? @"喜欢这条内容，就留下你的赞。" :
                        action == DYLikeActionFavorite ? @"保存到收藏，留待以后回看。" : @"关注后，更方便找到对方的动态。";
    NSString *confirmTitle = [@"确认" stringByAppendingString:verb];
    if (intent == DYLikeIntentRemove) {
        title = [NSString stringWithFormat:@"取消%@%@？", action == DYLikeActionFollow ? @"关注" : @"这次", action == DYLikeActionFollow ? @"这位用户" : verb];
        message = [NSString stringWithFormat:@"确认后将取消对%@的%@。", object, verb];
        confirmTitle = @"确认取消";
        if (action == DYLikeActionFollow) symbol = @"person.badge.minus";
    } else if (intent == DYLikeIntentToggle) {
        title = [NSString stringWithFormat:@"更改%@状态？", verb];
        message = [NSString stringWithFormat:@"确认后将切换%@的%@状态。", object, verb];
        confirmTitle = @"确认更改";
    }

    self.panel = [UIView new];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.panel.layer.cornerRadius = 8;
    self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    self.panel.clipsToBounds = YES;
    [self addSubview:self.panel];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    [self.panel addSubview:scroll];
    UIStackView *content = [UIStackView new];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 12;
    content.alignment = UIStackViewAlignmentFill;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightSemibold]]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = DYLikeAccent(action);
    icon.isAccessibilityElement = NO;
    [icon.heightAnchor constraintEqualToConstant:40].active = YES;
    [content addArrangedSubview:icon];
    self.heading = [self labelWithText:title size:20 weight:UIFontWeightSemibold];
    self.heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [content addArrangedSubview:self.heading];
    if (name.length) {
        UILabel *nameLabel = [self labelWithText:name size:16 weight:UIFontWeightMedium];
        nameLabel.numberOfLines = 3;
        nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [content addArrangedSubview:nameLabel];
    }
    UILabel *body = [self labelWithText:message size:15 weight:UIFontWeightRegular];
    body.textColor = UIColor.secondaryLabelColor;
    [content addArrangedSubview:body];

    self.buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self buttonWithTitle:@"取消" primary:NO accent:DYLikeAccent(action)],
        [self buttonWithTitle:confirmTitle primary:YES accent:DYLikeAccent(action)]
    ]];
    self.buttons.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttons.spacing = 12;
    self.buttons.distribution = UIStackViewDistributionFillEqually;
    [self.panel addSubview:self.buttons];
    [self updateButtonAxis];

    NSLayoutConstraint *preferredWidth = [self.panel.widthAnchor constraintEqualToConstant:360];
    preferredWidth.priority = 999;
    NSLayoutConstraint *contentHeight = [scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];
    contentHeight.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        preferredWidth,
        [self.panel.widthAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.widthAnchor constant:-40],
        [self.panel.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor],
        [self.panel.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor],
        [self.panel.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
        [self.panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [scroll.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:24],
        [scroll.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:24],
        [scroll.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-24],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:44], contentHeight,
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [self.buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:24],
        [self.buttons.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:20],
        [self.buttons.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-20],
        [self.buttons.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-20]
    ]];
}

- (void)updateButtonAxis {
    self.buttons.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ?
        UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
}

- (void)updateTheme {
    UIUserInterfaceStyle style = DYLikeUserInterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateTheme];
    [self updateButtonAxis];
}

- (void)confirm { [self finish:YES]; }
- (void)cancel { [self finish:NO]; }
- (BOOL)accessibilityPerformEscape { [self cancel]; return YES; }

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window && self.decision && !self.finishing) {
        self.finishing = YES;
        void (^decision)(BOOL) = self.decision;
        self.decision = nil;
        DYLikeVisiblePrompt = nil;
        [NSNotificationCenter.defaultCenter removeObserver:self];
        dispatch_async(dispatch_get_main_queue(), ^{ decision(NO); });
    }
}

- (void)finish:(BOOL)confirmed {
    if (self.finishing) return;
    self.finishing = YES;
    self.buttons.userInteractionEnabled = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    void (^decision)(BOOL) = self.decision;
    self.decision = nil;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.15 animations:^{
        self.alpha = 0;
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
        DYLikeVisiblePrompt = nil;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
        dispatch_async(dispatch_get_main_queue(), ^{ if (decision) decision(confirmed); });
    }];
}

+ (void)showStaleNotice {
    UIWindow *window = DYLikeActiveWindow();
    if (!window) return;
    UILabel *label = [UILabel new];
    label.overrideUserInterfaceStyle = DYLikeUserInterfaceStyle();
    label.text = @"内容已变化，本次操作已取消";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.textColor = UIColor.labelColor;
    label.backgroundColor = UIColor.secondarySystemBackgroundColor;
    label.layer.cornerRadius = 8;
    label.clipsToBounds = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:16],
        [label.widthAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.widthAnchor constant:-40],
        [label.heightAnchor constraintGreaterThanOrEqualToConstant:48]
    ]];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, label.text);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [label removeFromSuperview]; });
}
@end

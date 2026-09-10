#import "DYLikeCore.h"
#import "../UI/DYLikePrompt.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const DYLikeVersion = @"1.0-1";
NSString *const DYLikeRepositoryURL = @"https://github.com/jijiang2333/DYSecondaryConfirmation";
NSString *const DYLikeAuthor = @"JiJiang778";
NSString *const DYLikeLikeEnabledKey = @"DYLikeConfirmLike";
NSString *const DYLikeFavoriteEnabledKey = @"DYLikeConfirmFavorite";
NSString *const DYLikeFollowEnabledKey = @"DYLikeConfirmFollow";
NSNotificationName const DYLikeThemeDidChangeNotification = @"DYLikeThemeDidChange";

static __thread NSUInteger DYLikeReplayDepth[3];
static __thread DYLikeIntent DYLikeReplayIntent[3];

void DYLikeEnsureDefaults(void) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        DYLikeLikeEnabledKey: @NO, DYLikeFavoriteEnabledKey: @NO, DYLikeFollowEnabledKey: @NO
    }];
}

BOOL DYLikeEnabled(DYLikeActionType action) {
    NSString *key = action == DYLikeActionLike ? DYLikeLikeEnabledKey :
                    action == DYLikeActionFavorite ? DYLikeFavoriteEnabledKey : DYLikeFollowEnabledKey;
    return [NSUserDefaults.standardUserDefaults boolForKey:key];
}

BOOL DYLikeIsReplaying(DYLikeActionType action) {
    return action <= DYLikeActionFollow && DYLikeReplayDepth[action] > 0;
}

id DYLikeRead(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

UIWindow *DYLikeActiveWindow(void) {
    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha < 0.01 || window.windowLevel != UIWindowLevelNormal) continue;
            if (window.isKeyWindow) return window;
            if (window.rootViewController) candidate = window;
        }
    }
    if (!candidate && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
            if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
                if (window.isKeyWindow) return window;
                candidate = window;
            }
        }
    }
    return candidate;
}

UIColor *DYLikeAccent(DYLikeActionType action) {
    switch (action) {
        case DYLikeActionLike: return [UIColor colorWithRed:0.86 green:0.12 blue:0.26 alpha:1];
        case DYLikeActionFavorite: return [UIColor colorWithRed:0.65 green:0.40 blue:0.04 alpha:1];
        case DYLikeActionFollow: return [UIColor colorWithRed:0.02 green:0.49 blue:0.43 alpha:1];
    }
    return UIColor.systemBlueColor;
}

// 读取抖音当前背景主题。
UIUserInterfaceStyle DYLikeUserInterfaceStyle(void) {
    Class manager = NSClassFromString(@"AWEUIThemeManager");
    SEL selector = NSSelectorFromString(@"isLightTheme");
    Method method = class_getClassMethod(manager, selector);
    if (method) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == 'B') {
            return ((BOOL (*)(id, SEL))objc_msgSend)(manager, selector) ?
                UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
        }
    }
    UIUserInterfaceStyle style = DYLikeActiveWindow().traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
}

static void DYLikeNotifyThemeChange(void) {
    static BOOL scheduled;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (scheduled) return;
        scheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            scheduled = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:DYLikeThemeDidChangeNotification object:nil];
        });
    });
}

void DYLikeInstallThemeHooks(void) {
    static BOOL installed[3];
    NSArray *selectors = @[@"changeThemeStyleLightModeEnable:", @"setLightMode:", @"setThemeStyle:"];
    for (NSUInteger i = 0; i < selectors.count; i++) {
        if (installed[i]) continue;
        Class cls = NSClassFromString(i == 2 ? @"AWEThemeManager" : @"AWESettingThemeManager");
        if (i == 2) cls = object_getClass(cls);
        SEL selector = NSSelectorFromString(selectors[i]);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.methodReturnType[0] != 'v' || signature.numberOfArguments != 3 ||
            [signature getArgumentTypeAtIndex:2][0] != (i == 2 ? 'Q' : 'B')) continue;
        IMP original = method_getImplementation(method);
        IMP replacement;
        if (i == 2) {
            replacement = imp_implementationWithBlock(^(id owner, unsigned long long style) {
                ((void (*)(id, SEL, unsigned long long))original)(owner, selector, style);
                DYLikeNotifyThemeChange();
            });
        } else {
            replacement = imp_implementationWithBlock(^(id owner, BOOL light) {
                ((void (*)(id, SEL, BOOL))original)(owner, selector, light);
                DYLikeNotifyThemeChange();
            });
        }
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        installed[i] = YES;
    }
}

static NSString *DYLikeString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

// 从操作对象和页面上下文查找对应的用户或作品模型。
static id DYLikeFindModel(id root, DYLikeActionType action, NSUInteger depth, NSHashTable *visited) {
    if (!root || depth > 4 || [visited containsObject:root]) return nil;
    [visited addObject:root];
    if (action == DYLikeActionFollow) {
        Class profileCell = NSClassFromString(@"AWEProfileHeaderFollowAreaCell");
        if (profileCell && [root isKindOfClass:profileCell]) {
            id context = DYLikeRead(root, @"context");
            return DYLikeRead(context, @"userModel") ?: DYLikeRead(DYLikeRead(root, @"relationView"), @"userModel") ?: context;
        }
        id userModel = DYLikeRead(root, @"userModel");
        if (userModel && (DYLikeRead(userModel, @"userID") || DYLikeRead(userModel, @"userId") ||
                          DYLikeRead(userModel, @"secUserID") || DYLikeRead(userModel, @"uid"))) {
            return userModel;
        }
        if (DYLikeRead(root, @"userID") || DYLikeRead(root, @"userIDStr") || DYLikeRead(root, @"userId") ||
            DYLikeRead(root, @"secUserID") || DYLikeRead(root, @"secUserId") || DYLikeRead(root, @"uid")) return root;
    } else if (DYLikeRead(root, @"userDigged") || DYLikeRead(root, @"isCollected") ||
               DYLikeRead(root, @"commentID") || DYLikeRead(root, @"roomID")) {
        return root;
    }
    NSArray *keys = action == DYLikeActionFollow ?
        @[@"userModel", @"followContext", @"headerContext", @"context", @"relationView",
          @"currentOwner", @"currentUser", @"user", @"userProfile", @"viewModel", @"store",
          @"realShowAuthor", @"author", @"owner", @"model", @"aweme", @"awemeModel", @"room", @"data"] :
        @[@"comment", @"aweme", @"awemeModel", @"model", @"viewModel", @"interactor", @"context",
          @"cellModel", @"room", @"store", @"data"];
    for (NSString *key in keys) {
        id model = DYLikeFindModel(DYLikeRead(root, key), action, depth + 1, visited);
        if (model) return model;
    }
    return nil;
}

static id DYLikeModel(id root, DYLikeActionType action) {
    id model = DYLikeFindModel(root, action, 0, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
    if (model) return model;
    if ([root isKindOfClass:UIResponder.class]) {
        UIResponder *responder = [root nextResponder];
        for (NSUInteger i = 0; responder && i < 8; i++, responder = responder.nextResponder) {
            model = DYLikeFindModel(responder, action, 0, [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality]);
            if (model) return model;
        }
    }
    return nil;
}

static NSString *DYLikeIdentity(id model) {
    for (NSString *key in @[@"commentID", @"userID", @"userIDStr", @"userId", @"secUserID", @"secUserId", @"uid", @"itemID", @"roomID", @"aid"]) {
        NSString *value = DYLikeString(DYLikeRead(model, key));
        if (value.length) return [key stringByAppendingFormat:@":%@", value];
    }
    if ([model isKindOfClass:NSString.class] || [model isKindOfClass:NSNumber.class]) return DYLikeString(model);
    return model ? [NSString stringWithFormat:@"%p", model] : nil;
}

static NSNumber *DYLikeFollowState(long long status) {
    switch (status) {
        case 0: return @NO;
        case 1: case 2: case 4: return @YES;
        default: return nil;
    }
}

static NSNumber *DYLikeState(id model, DYLikeActionType action) {
    if (action == DYLikeActionFollow) {
        id shouldFollow = DYLikeRead(model, @"shouldFollowWhenTappedFollowButton");
        if ([shouldFollow isKindOfClass:NSNumber.class]) return @(![shouldFollow boolValue]);
        id following = DYLikeRead(model, @"following");
        if ([following isKindOfClass:NSNumber.class]) return @([following boolValue]);
        id followInfo = DYLikeRead(model, @"followInfo");
        id status = DYLikeRead(model, @"followStatus") ?: DYLikeRead(followInfo, @"followStatus");
        if ([status isKindOfClass:NSNumber.class]) {
            return DYLikeFollowState([status longLongValue]);
        }
        return nil;
    }
    NSArray *keys = action == DYLikeActionLike ? @[@"userDigged", @"isLiked"] :
                    @[@"isCollected", @"collectStatus", @"isFavorite"];
    for (NSString *key in keys) {
        id value = DYLikeRead(model, key);
        if ([value isKindOfClass:NSNumber.class]) return value;
    }
    return nil;
}

// 读取当前按钮对应的操作状态。
static NSNumber *DYLikeActionState(id owner, id model, DYLikeActionType action) {
    if (action == DYLikeActionFollow) {
        Class component = NSClassFromString(@"AWEProfileFollowAreaFollowComponent");
        id context = DYLikeRead(owner, @"headerContext");
        SEL effectiveStatus = NSSelectorFromString(@"effectiveFollowStatusWithHeaderContext:");
        Method method = class_getClassMethod(component, effectiveStatus);
        if (context && method && [owner isKindOfClass:component]) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 3 && signature.methodReturnType[0] == 'q' &&
                [signature getArgumentTypeAtIndex:2][0] == '@') {
                NSNumber *state = DYLikeFollowState(((long long (*)(id, SEL, id))objc_msgSend)(component, effectiveStatus, context));
                if (state) return state;
            }
        }
        NSNumber *visibleState = DYLikeState(DYLikeRead(owner, @"relationView"), action);
        if (visibleState) return visibleState;
        return DYLikeState(model, action) ?: DYLikeState(owner, action);
    }
    return DYLikeState(model, action) ?: DYLikeState(owner, action);
}

static BOOL DYLikeEqual(id a, id b) { return a == b || [a isEqual:b]; }

@interface DYLikeRequestTicket : NSObject
@property(nonatomic) DYLikeActionType action;
@property(nonatomic) DYLikeIntent intent;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic) BOOL consumed;
@property(nonatomic, copy) NSString *identity;
@end
@implementation DYLikeRequestTicket
@end

static char DYLikeTicketKey;
// 为单次请求记录目标用户与已确认的操作方向。
static void DYLikeMarkRequest(id request, id owner, DYLikeActionType action, DYLikeIntent intent, BOOL replace) {
    if (!request) return;
    NSString *cls = NSStringFromClass([request class]);
    if (![@[@"AWEInteractionDiggConfig", @"AWEInteractionToggleFavoriteAwemeConfig", @"AWEUserRelationContext", @"IESLiveUserFollowModel"] containsObject:cls]) return;
    if (!replace && objc_getAssociatedObject(request, &DYLikeTicketKey)) return;
    NSString *identity = DYLikeIdentity(DYLikeModel(request, action) ?: DYLikeModel(owner, action));
    if (!identity) return;
    DYLikeRequestTicket *ticket = [DYLikeRequestTicket new];
    ticket.action = action;
    ticket.intent = intent;
    ticket.deadline = NSProcessInfo.processInfo.systemUptime + 30;
    ticket.identity = identity;
    objc_setAssociatedObject(request, &DYLikeTicketKey, ticket, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 执行已确认操作，并在本次调用链内传递取消关注状态。
static void DYLikeRunApproved(DYLikeActionType action, DYLikeIntent intent,
                               dispatch_block_t operation, dispatch_block_t confirmedUnfollow) {
    BOOL unfollow = action == DYLikeActionFollow && intent == DYLikeIntentRemove;
    DYLikeIntent previousIntent = DYLikeReplayIntent[action];
    DYLikeReplayDepth[action]++;
    DYLikeReplayIntent[action] = intent;
    @try {
        if (unfollow && confirmedUnfollow) confirmedUnfollow();
        else operation();
    } @finally {
        DYLikeReplayIntent[action] = previousIntent;
        DYLikeReplayDepth[action]--;
    }
}

void DYLikeGuard(DYLikeActionType action, DYLikeIntent intent, id owner, id subject,
                 dispatch_block_t operation, dispatch_block_t cancellation, dispatch_block_t confirmedUnfollow) {
    if (!operation) return;
    if (!DYLikeEnabled(action)) {
        operation();
        return;
    }
    if (DYLikeIsReplaying(action)) {
        DYLikeIntent approvedIntent = intent == DYLikeIntentToggle ? DYLikeReplayIntent[action] : intent;
        DYLikeMarkRequest(subject, owner, action, approvedIntent, NO);
        operation();
        return;
    }
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DYLikeGuard(action, intent, owner, subject, operation, cancellation, confirmedUnfollow);
        });
        return;
    }
    DYLikeRequestTicket *ticket = subject ? objc_getAssociatedObject(subject, &DYLikeTicketKey) : nil;
    if (ticket && !ticket.consumed && ticket.action == action &&
        (action != DYLikeActionFollow || ticket.intent == intent || intent == DYLikeIntentToggle) &&
        ticket.deadline >= NSProcessInfo.processInfo.systemUptime &&
        DYLikeEqual(ticket.identity, DYLikeIdentity(DYLikeModel(subject, action) ?: DYLikeModel(owner, action)))) {
        ticket.consumed = YES;
        DYLikeRunApproved(action, ticket.intent, operation, confirmedUnfollow);
        return;
    }
    id root = subject ?: owner;
    BOOL scalarSubject = [subject isKindOfClass:NSString.class] || [subject isKindOfClass:NSNumber.class];
    id model = scalarSubject ? subject : DYLikeModel(root, action) ?: DYLikeModel(owner, action);
    NSString *identity = DYLikeIdentity(model);
    NSString *ownerIdentity = DYLikeIdentity(DYLikeModel(owner, action));
    NSNumber *state = DYLikeActionState(owner, model, action);
    UIView *sourceView = [owner isKindOfClass:UIView.class] ? owner : DYLikeRead(owner, @"view");
    if (![sourceView isKindOfClass:UIView.class]) sourceView = nil;
    UIWindow *sourceWindow = sourceView.window;
    DYLikeIntent effectiveIntent = intent;
    if (intent == DYLikeIntentToggle && state) {
        effectiveIntent = state.boolValue ? DYLikeIntentRemove : DYLikeIntentAdd;
    }
    NSString *name = action == DYLikeActionFollow ?
        DYLikeString(DYLikeRead(model, @"nickname") ?: DYLikeRead(model, @"nickName")) : nil;
    BOOL isComment = DYLikeRead(model, @"commentID") != nil;
    [DYLikePrompt presentForAction:action intent:effectiveIntent name:name isComment:isComment
                         decision:^(BOOL confirmed) {
        if (!confirmed) {
            if (cancellation) cancellation();
            return;
        }
        id current = scalarSubject ? subject : DYLikeModel(root, action) ?: DYLikeModel(owner, action);
        BOOL valid = UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
                     DYLikeEqual(identity, DYLikeIdentity(current)) &&
                     DYLikeEqual(ownerIdentity, DYLikeIdentity(DYLikeModel(owner, action))) &&
                     DYLikeEqual(state, DYLikeActionState(owner, current, action)) &&
                     (!sourceWindow || sourceView.window == sourceWindow);
        if (!valid) {
            if (cancellation) cancellation();
            [DYLikePrompt showStaleNotice];
            return;
        }
        DYLikeMarkRequest(subject, owner, action, effectiveIntent, YES);
        DYLikeRunApproved(action, effectiveIntent, operation, confirmedUnfollow);
    }];
}

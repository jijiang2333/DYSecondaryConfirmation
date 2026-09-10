#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, DYLikeActionType) {
    DYLikeActionLike,
    DYLikeActionFavorite,
    DYLikeActionFollow,
};

typedef NS_ENUM(NSUInteger, DYLikeIntent) {
    DYLikeIntentToggle,
    DYLikeIntentAdd,
    DYLikeIntentRemove,
};

FOUNDATION_EXPORT NSString *const DYLikeVersion;
FOUNDATION_EXPORT NSString *const DYLikeRepositoryURL;
FOUNDATION_EXPORT NSString *const DYLikeAuthor;
FOUNDATION_EXPORT NSString *const DYLikeLikeEnabledKey;
FOUNDATION_EXPORT NSString *const DYLikeFavoriteEnabledKey;
FOUNDATION_EXPORT NSString *const DYLikeFollowEnabledKey;
FOUNDATION_EXPORT NSNotificationName const DYLikeThemeDidChangeNotification;

FOUNDATION_EXPORT void DYLikeEnsureDefaults(void);
FOUNDATION_EXPORT BOOL DYLikeEnabled(DYLikeActionType action);
FOUNDATION_EXPORT BOOL DYLikeIsReplaying(DYLikeActionType action);
FOUNDATION_EXPORT id DYLikeRead(id object, NSString *key);
FOUNDATION_EXPORT UIWindow *DYLikeActiveWindow(void);
FOUNDATION_EXPORT UIColor *DYLikeAccent(DYLikeActionType action);
FOUNDATION_EXPORT UIUserInterfaceStyle DYLikeUserInterfaceStyle(void);
FOUNDATION_EXPORT void DYLikeInstallThemeHooks(void);

// 根据开关和操作状态显示确认弹窗，确认后执行对应操作。
FOUNDATION_EXPORT void DYLikeGuard(DYLikeActionType action, DYLikeIntent intent,
                                  id owner, id subject, dispatch_block_t operation,
                                  dispatch_block_t cancellation, dispatch_block_t confirmedUnfollow);

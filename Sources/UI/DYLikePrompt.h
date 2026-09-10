#import "../Core/DYLikeCore.h"

@interface DYLikePrompt : UIView
+ (void)presentForAction:(DYLikeActionType)action intent:(DYLikeIntent)intent
                    name:(NSString *)name isComment:(BOOL)isComment
                decision:(void (^)(BOOL confirmed))decision;
+ (void)showStaleNotice;
@end

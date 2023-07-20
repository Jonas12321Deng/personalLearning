//
//  WXBrowserViewController.h
//  CommonBusiness_Example
//
//  Created by tsy on 2020/3/8.
//  Copyright © 2020年 707002468@qq.com. All rights reserved.
//

#import "RootViewController.h"
#import "WXWebViewCommonModel.h"
#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface WXBrowserViewController : RootViewController

/**
 能否分享
 */
@property(nonatomic,assign)BOOL canShare;

/**
 点击返回按钮是否离开该页面。默认NO
 */
@property(nonatomic,assign)BOOL closedAllWeb;

/**
 业务类型
 */
@property(nonatomic,assign) WebBusinessType businessType;

/**
 屏幕方向
 */
@property(nonatomic,assign) WebScreenType screenType;

/**
 状态栏字体颜色是否为dark类型
 */
@property(nonatomic,assign) BOOL isStatusBarContentDark;


@property (nonatomic,weak) id<WXBrowserViewControllerDelegate> onlineDelegate;

/// 是否需要自动旋转，默认为YES
@property (nonatomic) BOOL overrideShouldAutorotate;

#pragma mark - func

- (instancetype)initWithUrlStr:(NSString *)urlStr;

/// 动态加入额外的cookie
/// @param cookieValue cookie的值
/// @param key cookie的key
- (void)addCookie:(NSString *)cookieValue forKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END

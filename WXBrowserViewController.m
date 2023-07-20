//
//  WXBrowserViewController.m
//  CommonBusiness_Example
//
//  Created by tsy on 2020/3/8.
//  Copyright © 2020年 707002468@qq.com. All rights reserved.
//

#import "WXBrowserViewController.h"
#import "WXWebViewNavigationView.h"
#import "AppConfigManager.h"
#import "XrsBury.h"
#import "XrsLog.h"
#import "WXAlarmLog.h"
#import "xesApp.h"
#import "xesApp+wk.h"
#import <XRSJumpCenter/XRSJumpCenter.h>
#import "WeChatShareManager.h"
#import "WXAttainimentKeyBoardView.h"
#import "MttAlertController.h"
#import <WXEnvConfig/WXEnvConfig.h>
#import <TALHybridKit/TALHybridKit.h>
#import "BuglyAgentUtil.h"
#import <WXBurySDK/WXBuryManager.h>
#import "WXJsBridge+Voice.h"
#import "WXJsBridgeImageSaveManager.h"
#import "WXTransitionAnimation.h"
#import "WXBrowserMemoryMonitorController.h"
#import "WXBrowserPlayerView.h"
#import "WXPreloadMgr.h"
#import "WXCookieTool.h"
#import "WKWebView+WXExtension.h"

#if ENABLE_DEBUG_MOD
#import <WXDebugKit/WXDebugManager.h>

#endif

#define SuppressPerformSelectorLeakWarning(Stuff) \
do { \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Warc-performSelector-leaks\"") \
Stuff; \
_Pragma("clang diagnostic pop") \
} while (0)

typedef NS_ENUM(NSUInteger, WXBasicEventType) {
    WXBasicEventTypeViewWillAppear,//即将出现
    WXBasicEventTypeViewWillDisappear,//即将消失
    WXBasicEventTypeEnterBackground,//进入后台
    WXBasicEventTypeEnterForeground,//进入前台
    WXBasicEventTypeLeftButtonClick,//左侧按钮点击
    WXBasicEventTypeRightButtonClick,//右侧按钮点击
    WXBasicEventTypeDealloc //H5页面销毁
};


@interface WXBrowserViewController ()<WKNavigationDelegate,WKScriptMessageHandler,WKUIDelegate,UIGestureRecognizerDelegate,WXShareViewDel, WXAttainimentKeyBoardViewDelegate,xesAppDelegate,WXJsBridgeDelegate,UIViewControllerTransitioningDelegate,THScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WXShareView * shareView;
@property (nonatomic, strong) WXWebViewNavigationView *customNavigationView;
@property (nonatomic, strong) WXBrowserPlayerView *playerView;

@property (nonatomic, strong) xesAppWk *xesappWk;
@property (nonatomic, strong) WXJsBridge *jsBridge;
@property (nonatomic, strong) NSMutableDictionary  *jsObjects;
@property(nonatomic,strong) WXAttainimentKeyBoardView *keyBoardViewManager;

@property (nonatomic, copy) NSString *urlStr;
@property (nonatomic, copy) NSString *orginalUrlStr;
@property (nonatomic, strong) NSMutableArray *photos;
@property (nonatomic, strong) NSString *loginCallBackMethodString;
@property (nonatomic, strong) NSMutableDictionary *expendCookies;
@property (nonatomic, strong) NSDictionary *schemeParams;
@property (nonatomic, copy) NSString *startLoadTime;
@property (nonatomic, copy) NSString *refererStr;         //用于h5调用微信支付

@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, assign) BOOL statusBarHidden;
@property (nonatomic, assign) BOOL needGetWebTitle;

@property (nonatomic, copy) NSString *shareDesc;
@property (nonatomic, copy) NSString *shareTitle;
@property (nonatomic, copy) NSString *shareUrl;
@property (nonatomic, copy) NSString *shareImagePath;

@property(nonatomic, strong) WXTransitionAnimation *animation;
@property(nonatomic,assign) BOOL cancelNavPopGesture;
@property(nonatomic,assign) WKNavigationType navigationType;

@property(nonatomic, strong) WXBrowserMemoryMonitorController *memoryMonitor;
@end


@implementation WXBrowserViewController

#pragma mark - Override

- (void)dealloc
{
    // 非登录态页面销毁时清空sourceId
    if (![[MyUserInfoDefaults sharedDefaults] isLogInStatus])
    {
        [[WXAnalyticsSDK sharedSDK] clearSourceId];
    }
        
    // 移除注册的messageHandler
    if (_webView)
    {
        NSArray *names = @[@"xesJsBridge",@"jsContext",@"showImages", @"xesApp"];
        for (NSString *name in names) {
            [_webView.configuration.userContentController removeScriptMessageHandlerForName:name];
        }
        [self basicEventCallbackWithType:WXBasicEventTypeDealloc completion:nil];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
        
    // 移除观察者
    [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [_webView removeObserver:self forKeyPath:@"title"];
    
    _webView.wx_UIDelegate = nil;
    _webView.wx_navigationDelegate = nil;
    //停止内存监测
    [_memoryMonitor stopMonitor];
}


- (id)initWithXRSJumpDic:(NSDictionary*)dicParam {
    _schemeParams = dicParam;
    NSString *url = [dicParam objectForKey:@"url"];
    return [self initWithUrlStr:url];
}

- (instancetype)init{
    if (self = [super init]) {
        self.jsObjects = [[NSMutableDictionary alloc] initWithCapacity:2];
        self.isStatusBarContentDark = YES;
        _overrideShouldAutorotate = YES;
    }
    return self;
}

- (instancetype)initWithUrlStr:(NSString *)urlStr {
    if (self = [super init]) {
        _canShare = YES;
        self.isStatusBarContentDark = YES;
        self.jsObjects = [[NSMutableDictionary alloc] initWithCapacity:2];
        [BuglyAgentUtil buglyInfo:urlStr];
        if([urlStr rangeOfString:@"://"].location == NSNotFound)
        {
            urlStr = [NSString stringWithFormat:@"https://%@",urlStr];
        }
        
        if (urlStr == nil)
        {
            urlStr = [WXAppHostConfig getH5MainDomainName];
        }
        
        // 对url做处理
        urlStr = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,(CFStringRef)urlStr, (CFStringRef)@"!$&'()*+,-./:;=?@_~%#[]",NULL,kCFStringEncodingUTF8));;
        
        _urlStr = urlStr;
        _orginalUrlStr = urlStr;
        
        [self configWithUrlStr:urlStr];
    }
    return self;
}

- (void)configWithUrlStr:(NSString *)urlStr
{
    NSURL *URL = [NSURL URLWithString:urlStr];
    NSString *query = URL.query;
    if (query == nil && [urlStr containsString:@"?"]) {
        NSArray *arr = [urlStr componentsSeparatedByString:@"?"];
        if (arr.count > 1) {
            query = [arr wx_objectAtIndex:1];
        }
    }
    NSDictionary *queryDic = [StringValidUtil convertQueryToDic:query];
    
    // 设置导航栏样式
    [self updateNavigationBar:nil];
    
    // 设置屏幕旋转
    [self setSupportedInterfaceOrientationInfoWithURL:URL];
    
    //如果需要加载评论组件就赋值itemid
    NSString *itemId = [queryDic objectForKey:@"itemId"];
    if (itemId.length == 0) {
        itemId = [queryDic objectForKey:@"resoid"];
    }
    if (itemId.length > 0) {
        self.keyBoardViewManager.itemid = itemId;
    }
}

// 设置屏幕支持的旋转方向
- (void)setSupportedInterfaceOrientationInfoWithURL:(NSURL *)URL {
    NSString *query = URL.query;
    if (query == nil && [URL.absoluteString containsString:@"?"]) {
        NSArray *arr = [URL.absoluteString componentsSeparatedByString:@"?"];
         if (arr.count > 1) {
            query = [arr wx_objectAtIndex:1];
         }
    }
    NSDictionary *queryDic = [StringValidUtil convertQueryToDic:query];
    
    // 设置屏幕旋转
    _screenType = kWebScreenType_Portrait;
    NSInteger screenType = [[queryDic objectForKey:@"screenType"] intValue];
    if (screenType == 1) {
        _screenType = kWebScreenType_Landscape;
    }
    else if (screenType == 2)
    {
        _screenType = kWebScreenType_AllButUpsideDown;
    }
}

- (BOOL)prefersStatusBarHidden
{
    return self.statusBarHidden;
}

- (void)errorViewBackAction
{
    if (_webView.URL) {
        _noContentView.hidden = YES;
    }else {
        [super errorViewBackAction];
    }
}


- (CGFloat)navigationHeight
{
    if (IS_IPHONE_X){
        return kIPhoneXStatusBarHeight + kIphoneXNaviBarHeight;
    }else {
        return 64;
    }
}

- (NSDictionary *)buryPV_businessParams
{
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params wx_setObject:_urlStr forKey:@"url"];
    return params;
}

#pragma mark - life circle
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self basicEventCallbackWithType:WXBasicEventTypeViewWillAppear completion:nil];
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    if (_cancelNavPopGesture) {
        self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    }
//    if (self.screenType == 1) {
//        self.contentViewStyle = WXContentViewStyle_Landscape;
//    }
}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.statusBarHidden = NO;
    [self basicEventCallbackWithType:WXBasicEventTypeViewWillDisappear completion:nil];
}

-(void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    if(_onlineDelegate && [_onlineDelegate respondsToSelector:@selector(webViewDidClosed:)]){
        [_onlineDelegate webViewDidClosed:self];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.shouldHiddenNavBar = YES;
    
#if !ENABLE_DEBUG_MOD
    // 只在入口处做拦截
    if (self.urlStr && ![self allowLoadUrl:[NSURL URLWithString:self.urlStr]])
    {
        NSString *title = [NSString stringWithFormat:@"啊哦！%@不支持访问这个页面哟", [AppInfo appName]];

        [self showHaveImageNoConentView:self.wxContentView title:title refreshBlock:NULL];
        [(NoContentView *)_noContentView backBtnShouldShow:YES];
        
        // 添加告警
        [WXAlarmLog alarmEventId:@"url_wh_not_con" desc:@"白名单之外网页访问" content:self.urlStr extraInfo:nil];
        return;
    }
    
#else
    
    if ([WXDebugManager shareManager].htmlMemoryEnable) {
        [self.memoryMonitor startMonitor];
    }
    
#endif
    [self setUpUI];
    [self loadRequest];
    [self addNotifications];
    
    self.xesappWk.wkWebView = _webView;
    self.jsBridge.webView = _webView;
    self.customNavigationView.webView = _webView;
    
    [self postCreateBrowserEvent];
}

//- (void)setIPadWkUA:(WKWebView*)webview
//{
//    if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
//        NSString *userAgent = [WXH5UserAgentManager getUserAgent];
//        if(userAgent == nil)
//            return;
//        if (@available(iOS 9.0, *)) {
//            [webview setCustomUserAgent:userAgent];
//        }
//    }
//}


- (void)setUpUI {
    if (@available(iOS 11.0, *)) {
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.wxContentView.backgroundColor = [UIColor whiteColor];
    [self.wxContentView addSubview:self.webView];
    
    if (self.businessType == kWebBusinessType_LearnPreview) {
        //学心中进预习的设置
        [self.webView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.left.right.bottom.equalTo(@0);
        }];
        self.customNavigationView.hidden = YES;
        self.statusBarHidden = YES;
    }else {
        self.statusBarHidden = NO;
        [self.wxContentView addSubview:self.customNavigationView];
        
        [self.customNavigationView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.top.equalTo(@0);
            make.height.equalTo(@([self navigationHeight]));
        }];
        
        [self.webView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.bottom.equalTo(@0);
            make.top.equalTo(self.customNavigationView.styleType == WXWebViewNavigationBarTypeNormal ? @([self navigationHeight]):@0);
        }];
        
        [self.customNavigationView updateNavigationBarWithNavigationInfo:nil andURL:self.urlStr];
        
        [self.wxContentView addSubview:self.progressView];
        [self.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.equalTo(@0);
            make.top.equalTo(self.customNavigationView.mas_bottom);
            make.height.equalTo(@2);
        }];
    }
    
    if (!self.isStatusBarContentDark) {
        self.statusBarTextColor = WXStatusBarTextWhiteColor;
    }
    
    if (_screenType == kWebScreenType_Landscape) {
        self.contentViewStyle = WXContentViewStyle_Landscape;
    }
}

- (void)setContentViewStyle:(WXContentViewStyle)contentViewStyle {
    [super setContentViewStyle:contentViewStyle];
    if (contentViewStyle == WXContentViewStyle_Landscape) {
        CGFloat width = MAX(self.view.bounds.size.width, self.view.bounds.size.height);
        [self.wxContentView mas_updateConstraints:^(MASConstraintMaker *make) {
            make.width.mas_equalTo(width);
        }];
        [self.view layoutIfNeeded];
    }
}

- (void)updateWebViewLayout {
    
    CGFloat height = [self navigationHeight];
    CGFloat offset = 0;
    if (self.customNavigationView.styleType != WXWebViewNavigationBarTypeNormal || self.customNavigationView.hidden) {
        height = 0;
        offset = -44;
    }
    
    if (_progressView && _progressView.hidden == NO) {
        [self.progressView mas_updateConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.customNavigationView.mas_bottom).offset(offset);
        }];
    }
    
    [_webView mas_updateConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(@(height));
    }];
    
}

//-(NSURLRequest *)composingHeaderCookie:(NSMutableURLRequest*)request {
//    NSMutableString* cookie;
//    NSArray* cookieList = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:request.URL];
//    NSDictionary* cookieHeaderDict = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieList];
//    cookie = cookieHeaderDict[@"Cookie"];
//    [request setValue:cookie forHTTPHeaderField:@"Cookie"];
//    return request;
//}


- (void)loadRequest {
    
    if (@available(iOS 11.0, *)) {
        for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies]) {
            [self.webView.configuration.websiteDataStore.httpCookieStore setCookie:cookie completionHandler:nil];
        }
        NSSet *dataTypes = [NSSet setWithObject:WKWebsiteDataTypeCookies];
        WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
        [dataStore fetchDataRecordsOfTypes:dataTypes completionHandler:^(NSArray<WKWebsiteDataRecord *> * dataRecord) {
            
        }];
    }
    
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_orginalUrlStr] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:60.0f];
    [self.webView loadRequest:request];
}

- (void)addNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterBackGroundAction:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enterForeGroundAction:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(logInSuccessful:) name:kUserDidLoginSuccessfulNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(resignLogin:) name:kUserDidResignLogInNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(didChangeRotate:) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(endFullScreen) name:UIWindowDidBecomeHiddenNotification object:nil];
}

- (void)endFullScreen{
     [[UIApplication sharedApplication] setStatusBarHidden:self.statusBarHidden animated:NO];
}

#pragma mark - 添加cookies
- (void)addCookie:(NSString *)cookieValue forKey:(NSString *)key {
    [self.expendCookies wx_setObject:cookieValue forKey:key];
}

#pragma mark - 通知监听
- (void)didChangeRotate:(NSNotification*)notice {
    if (!self.overrideShouldAutorotate) {
        return;
    }
    CGFloat height = 64;
    if ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortrait
        || [UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationPortraitUpsideDown) {
        //竖屏
        height = [self navigationHeight];
        if (![UIScreen isIpadLand]) {
            _shareView = [WXShareView shareView];
            _shareView.delegate = self;
            self.contentViewStyle = WXContentViewStyle_Portrait;
        }
    }else {
        if (![UIScreen isIpadLand]) {
            _shareView = [WXShareView shareView];
            _shareView.delegate = self;
            self.contentViewStyle = WXContentViewStyle_Landscape;
        }
    }
    if (self.customNavigationView.styleType == WXWebViewNavigationBarTypeNormal && self.customNavigationView.hidden == NO) {
        [self.customNavigationView mas_updateConstraints:^(MASConstraintMaker *make) {
            make.height.equalTo(@(height));
        }];
        [self.webView mas_updateConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(@(height));
        }];
    }
}

- (void)logInSuccessful:(NSNotification *)notifity {
    
    // 白名单域添加tal_token
    [WXCookieTool webviewSynchronizeCookies:self.expendCookies url:_urlStr];
    
    if (self.jsBridge.autoReloadAfterLogin) {
        [self loadRequest];
    }
    
    if (![WXEmptyUtils isEmptyString:self.loginCallBackMethodString]) {
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"%@(%d)",self.loginCallBackMethodString,1] completionHandler:nil];
    }
}

- (void)enterBackGroundAction:(NSNotification *)notifity {
    [self basicEventCallbackWithType:WXBasicEventTypeEnterBackground completion:nil];
}

- (void)enterForeGroundAction:(NSNotification *)notifity {
    [self basicEventCallbackWithType:WXBasicEventTypeEnterForeground completion:nil];
}

- (void)resignLogin:(NSNotificationCenter *)notifity {
    if (![WXEmptyUtils isEmptyString:self.loginCallBackMethodString]) {
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"%@(%d)",self.loginCallBackMethodString,0] completionHandler:nil];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (object == _webView && [keyPath isEqualToString:@"estimatedProgress"])
    {
        CGFloat progress = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
        __weak typeof (self) weakSelf = self;
        void (^block)(void) =^{
            [weakSelf.progressView setProgress:progress animated:YES];
            if (progress < 1)
            {
                weakSelf.progressView.hidden = NO;
            }
            else
            {
                weakSelf.progressView.hidden = YES;
                weakSelf.progressView.progress = 0;
            }
        };
        if([[NSThread currentThread] isMainThread]){
            block();
        }
        else{
            dispatch_async(dispatch_get_main_queue(), ^{
                block();
            });
        }
    }else if ([keyPath isEqualToString:@"title"]) {
        if (object == self.webView) {
            [self.customNavigationView updateTitle:self.webView.title url:self.webView.URL.absoluteString];
        }
    }
}

#pragma mark - 交互事件

/**
 左侧按钮点击事件
 */
- (void)leftButtonAction {
    [self basicEventCallbackWithType:WXBasicEventTypeLeftButtonClick completion:^{
        [self webViewGoBack];
    }];
}

/**
 右侧按钮点击事件
 */
- (void)rightButtonAction {
    [self basicEventCallbackWithType:WXBasicEventTypeRightButtonClick completion:^{
        [self rightButtonActionHandle];
    }];
}

/// 右侧按钮点击事件处理
- (void)rightButtonActionHandle {
    if ([self.customNavigationView naviagtionInfoModel].callBackFunc.length > 0) {
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"%@()", [self.customNavigationView naviagtionInfoModel].callBackFunc] completionHandler:nil];
    }else {
        if (self.customNavigationView.optionType > 0) {
            [self clickItemListWithSupport:self.customNavigationView.optionType];
        }else if (self.canShare){
            [self clickItemListWithSupport:(WXTitleMenuTypeRefresh +  WXTitleMenuTypeShare + WXTitleMenuTypeClose)];
        }else{
            [self clickItemListWithSupport:WXTitleMenuTypeRefresh + WXTitleMenuTypeClose];
        }
    }
}

- (void)closeView {
    // 键盘收起后，返回上一界面
    [UIView animateWithDuration:0.1 animations:^{
        [self.wxContentView endEditing:YES];
    } completion:^(BOOL finished) {
        [super btnClick];
    }];
}

- (void)refreshBtnPress
{
    NSURL *URL = self.webView.URL;
    if (URL)
    {
        [self.webView reload];
    }
    else
    {
        // 首次加载失败时,webview.URL为nil，所以要再次构建request加载
        [self loadRequest];
    }
        
    // 埋点
    [XrsBury clickBury:@"click_16_02_001" businessInfo:nil];
}

//默认右按钮事件点击
-(void)clickItemListWithSupport:(NSInteger)support
{
    if (support & WXTitleMenuTypeShare)
    {
        // 支持分享
        [self.shareView layoutSubviewsWithShareScene:WXShareSceneAll | WXShareSceneRefreshPage | WXShareSceneClosePage];
    }
    else
    {
        // 不支持分享
        [self.shareView layoutSubviewsWithShareScene:WXShareSceneRefreshPage | WXShareSceneClosePage];
    }
        
    [self.shareView showAnimationAddToView:[UIApplication sharedApplication].keyWindow];
}

#pragma mark - setter


- (void)setIsPressedCourse:(NSNumber *)isPressedCourse {
    objc_setAssociatedObject(self, @selector(isPressedCourse), isPressedCourse, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setCanShare:(BOOL)canShare {
    if ([WXApi isWXAppInstalled] == 0) {
        _canShare = NO;
    }else {
        _canShare = canShare;
    }
}

#pragma mark - getter
- (NSNumber *)isPressedCourse {
    return objc_getAssociatedObject(self, @selector(isPressedCourse));
}

- (WKWebView *)webView {
    if (_webView == nil) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        config.userContentController = [[WKUserContentController alloc] init];
        
        NSString *jspath = [[NSBundle mainBundle] pathForResource:@"proxy" ofType:@"js"];
        NSString *jsContent = [NSString stringWithContentsOfFile:jspath encoding:NSUTF8StringEncoding error:nil];
        WKUserScript* userScript = [[WKUserScript alloc] initWithSource:jsContent injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
        
        [config.userContentController addUserScript:userScript];
        [config.userContentController addScriptMessageHandler:self name:@"xesJsBridge" nativeObj:nil];
        [config.userContentController addScriptMessageHandler:self name:@"jsContext" nativeObj:nil];
        [config.userContentController addScriptMessageHandler:self name:@"showImages" nativeObj:nil];
        [config.userContentController addScriptMessageHandler:self name:@"xesApp" nativeObj:nil];
        [config.userContentController addScriptMessageHandler:self name:@"WXJsBridge" nativeObj:self.jsBridge];
        config.allowsInlineMediaPlayback = YES;
        
        if (@available(iOS 10.0, *)) {
            config.mediaTypesRequiringUserActionForPlayback = NO;
        }
        _webView = [[WKWebView alloc] initWithFrame:self.wxContentView.bounds configuration:config preload:YES];
        _webView.wx_navigationDelegate = self;
        _webView.wx_UIDelegate = self;
        
        _webView.scrollView.showsVerticalScrollIndicator = NO;
        _webView.scrollView.showsHorizontalScrollIndicator = NO;
        if(@available(iOS 11.0, *)) {
            _webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
        [_webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
    }
    return _webView;
}

- (WXWebViewNavigationView *)customNavigationView {
    if (_customNavigationView == nil) {
        _customNavigationView = [[WXWebViewNavigationView alloc] init];
        [_customNavigationView.leftButton addTarget:self action:@selector(leftButtonAction) forControlEvents:UIControlEventTouchUpInside];
        [_customNavigationView.rightButton addTarget:self action:@selector(rightButtonAction) forControlEvents:UIControlEventTouchUpInside];
        __weak typeof(self) weakSelf = self;
        [_customNavigationView setChangeStatusStyleBlock:^(WXStatusBarTextColor statusBarType) {
            if (weakSelf.statusBarTextColor != statusBarType) {
                weakSelf.statusBarTextColor = statusBarType;
            }
        }];
    }
    return _customNavigationView;
}

- (NSMutableArray *)photos {
    if (_photos == nil) {
        _photos = [[NSMutableArray alloc] init];
    }
    return _photos;
}

- (UIProgressView *)progressView
{
    if (_progressView == nil)
    {
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectZero];
        _progressView.progressTintColor = [UIColor wx_colorWithHEXValue:0xE02727];
        _progressView.trackTintColor = [UIColor clearColor];
    }
    return _progressView;
}

- (WXShareView *)shareView {
    if (_shareView == nil){
        _shareView = [WXShareView shareView];
        _shareView.delegate = self;
    }
    return _shareView;
}


- (NSString *)shareDesc {
    if (_shareDesc) {
        return _shareDesc;
    }else {
        return [self.customNavigationView naviagtionInfoModel].title;
    }
}

- (NSString *)shareTitle {
    if (_shareTitle) {
        return _shareTitle;
    }else {
        return kXueErSiWangXiaoSloganText;
    }
}

- (NSString *)shareUrl {
    if (_shareUrl) {
        return _shareUrl;
    }else{
        return _urlStr;
    }
}

- (WXAttainimentKeyBoardView *)keyBoardViewManager {
    if (!_keyBoardViewManager) {
        _keyBoardViewManager = [[WXAttainimentKeyBoardView alloc] init];
        _keyBoardViewManager.delegate = self;
    }
    return _keyBoardViewManager;
}

- (xesAppWk *)xesappWk {
    if (_xesappWk == nil) {
        _xesappWk = [[xesAppWk alloc] init];
        _xesappWk.delegate = self;
        [self.jsObjects setValue:_xesappWk forKey:@"xesapp"];
    }
    return _xesappWk;
}

- (WXJsBridge *)jsBridge {
    if (_jsBridge == nil) {
        _jsBridge = [[WXJsBridge alloc] init];
        _jsBridge.delegate = self;
        [self.jsObjects setValue:_jsBridge forKey:@"WXJsBridge"];
    }
    
    return _jsBridge;
}

- (NSMutableDictionary *)expendCookies {
    if (_expendCookies == nil) {
        _expendCookies = [[NSMutableDictionary alloc] init];
    }
    return _expendCookies;
}

- (WXTransitionAnimation *)animation {
    if (_animation == nil) {
        _animation = [[WXTransitionAnimation alloc] init];
    }
    return _animation;
}

- (WXBrowserMemoryMonitorController *)memoryMonitor {
    if (_memoryMonitor == nil) {
        _memoryMonitor = [[WXBrowserMemoryMonitorController alloc] init];
    }
    return _memoryMonitor;
}

- (WXBrowserPlayerView *)playerView {
    if (_playerView == nil) {
        _playerView = [[WXBrowserPlayerView alloc] initWithFrame:self.wxContentView.bounds];
    }
    return _playerView;
}

#pragma mark - 系统功能
- (void)checkCapture {
    //获取相机权限
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (authStatus)
    {
        case AVAuthorizationStatusAuthorized: // 授权通过
        {
            break;
        }
        case AVAuthorizationStatusNotDetermined: // 未判断的
        {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                //这里是子线程，要操作ui请抛回主线程
                XESLog(@"授权通过!!!");
            }];
            break;
        }
        default:
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"请打开相机权限继续使用" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelButton = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                // Do something after clicking OK button
                
            }];
            UIAlertAction *okButton = [UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                // 无权限 引导去开启
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                if ([[UIApplication sharedApplication] canOpenURL:url]) {
                    [[UIApplication sharedApplication] openURL:url];
                }
            }];
            [alert addAction:okButton];
            [alert addAction:cancelButton];
            [self presentViewController:alert animated:YES completion:nil];
            break;
        }
    }
}

-(void)imagesvaePhoto{
    [self.jsBridge.imageManager saveImageToAlbumWithImage:[self.jsBridge.imageManager captureImageWithView:[UIApplication sharedApplication].keyWindow]];
}

- (void)saveImage:(UIImage *)image {
    __weak typeof(self) weakSelf = self;
    [self.jsBridge.imageManager setSaveImageCompletion:^(BOOL success) {
        [weakSelf saveImageCallBack:success];
    }];
    [self.jsBridge.imageManager saveImageToAlbumWithImage:image];
}

- (void)saveImageCallBack:(BOOL)success {
    if (self.xesappWk.shareJSCallBack.length > 0) {
        NSString * jsStr = [NSString stringWithFormat:@"%@(%d)",self.xesappWk.shareJSCallBack,success];
        [self.webView evaluateJavaScript:jsStr completionHandler:^(id _Nullable jsData, NSError * _Nullable error) {
            
        }];
    }
}

#pragma mark -WXAttainimentKeyBoardViewDelegate

- (void)submitComment:(WXAttainimentKeyBoardView *)view dic:(NSDictionary *)msg
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:msg options:kNilOptions error:nil];
    NSString *msgStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSString *jsString = [NSString stringWithFormat:@"keyboard('%@')",msgStr];
    [self.webView evaluateJavaScript:jsString completionHandler:^(id _Nullable data, NSError * _Nullable error) {
    }];
}

- (void)toastMsg:(WXAttainimentKeyBoardView *)view msg:(NSString *)msg {
    UIWindow *parentView = [[[UIApplication sharedApplication] delegate] window];
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (id windowView in windows) {
        NSString *viewName = NSStringFromClass([windowView class]);
        if ([@"UIRemoteKeyboardWindow" isEqualToString:viewName]) {
            parentView = windowView;
            break;
        }
    }
    [WXToastView showToastWithTitle:msg superView:parentView duration:2.0f];
}

- (void)startRecord {
    NSString *jsString = [NSString stringWithFormat:@"nativeAudioStatus('%d')",1];
    [self.webView evaluateJavaScript:jsString completionHandler:^(id _Nullable data, NSError * _Nullable error) {
    }];
}


#pragma mark - WKUIDelegate
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(nullable NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable result))completionHandler
{
    //jsbridge 标识，用于处理js 调用,过度时使用，以后还是统一走postmessage 那套
    if([defaultText isEqualToString:@"jsbridge3399348883"])
    {
        NSDictionary *dic = nil;
        @try {
            NSData *jsonData = [prompt dataUsingEncoding:NSUTF8StringEncoding];
            NSError *err;
            dic = [NSJSONSerialization JSONObjectWithData:jsonData  options:NSJSONReadingMutableContainers error:&err];
        } @catch (NSException *exception) {
        }
        NSString * moduleName = dic[@"moduleName"];
        NSString * funtionName = dic[@"functionName"];
        if(moduleName && funtionName)
        {
            
            //埋点
            NSString *eventId = [NSString stringWithFormat:@"jsBridge_%@_%@",moduleName,funtionName];
            [XrsLog postEventId:eventId label:nil attachment:nil];
            
            id jsObj = self.jsObjects[moduleName];
            if(jsObj)
            {
                SEL selector = NSSelectorFromString([NSString stringWithFormat:@"handleJsBridgeRequest_%@:", funtionName]);
                if ([jsObj respondsToSelector:selector])
                {
                    NSDictionary *query = nil;
                    if ([dic[@"params"] isKindOfClass:[NSDictionary class]]) {
                        query = dic[@"params"];
                    }
                    id ret;
                    SuppressPerformSelectorLeakWarning(ret = [jsObj performSelector:selector withObject:query]);
                    if([ret isKindOfClass:[NSNumber class]] || [ret isKindOfClass:[NSString class]])
                    {
                        NSMutableDictionary * retDic = [NSMutableDictionary new];
                        retDic[@"res"] = ret ? ret:@"";
                        completionHandler([retDic modelToJSONString]);
                        return;
                    }
                }
            }
        }
    }
    
    completionHandler(nil);
}

// 创建一个新的WebView
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures{
    
    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    
    return nil;
}

// 确认框
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler API_AVAILABLE(ios(8.0)){
    completionHandler(YES);
}
// 警告框
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(8.0)){
    
    MttAlertController *alert = [ MttAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak MttAlertController *weakAC = alert;
    alert.naBlock = completionHandler;
    
    UIAlertAction *action = [UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        weakAC.naBlock = nil;
        if (completionHandler) {
            completionHandler();
        }
    }];
    [alert addAction:action];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message API_AVAILABLE(ios(8.0))
{
    if([message.name isEqualToString:@"xesJsBridge"])
    {
        id body = message.body;
        if([body isKindOfClass:[NSArray class]] && [(NSArray*)body count] >=2 )
        {
            NSArray  *arr = (NSArray*) body;
            NSString *moduleName = arr[0];
            id jsObj = self.jsObjects[moduleName];
            if(jsObj)
            {
                NSString *funtionName = arr[1];
                SEL selector = NSSelectorFromString([NSString stringWithFormat:@"handleJsBridgeRequest_%@:", funtionName]);
                if ([jsObj respondsToSelector:selector])
                {
                    NSDictionary *query = nil;
                    if (arr.count > 2 && [arr[2] isKindOfClass:[NSDictionary class]]) {
                        query = arr[2];
                    }
                    
                    //学习报告截屏埋点
                    if (self.businessType == kWebBusinessType_StudyReport &&
                        [_orginalUrlStr rangeOfString:@"primaryReport=1"].location != NSNotFound &&
                        [funtionName isEqualToString:@"start"] &&
                        [[query wx_stringForKey:@"name"] isEqualToString:@"xesShare/share"]){
                        [XrsLog postEventId:@"StudyReportShareWebViewShareAction" label:nil attachment:nil];
                    }
                    /*--------------------------------*/
                    
                    SuppressPerformSelectorLeakWarning([jsObj performSelector:selector withObject:query]);
                }
                
                //埋点
                NSString *eventId = [NSString stringWithFormat:@"jsBridge_%@_%@",moduleName,funtionName];
                [XrsLog postEventId:eventId label:nil attachment:nil];
            }
        }
    }else if ([message.name isEqualToString:@"jsContext"]){
        if ([message.body isKindOfClass:[NSArray class]] && [message.body count] == 2) {
            NSArray  *arr = (NSArray*)message.body;
            NSString *funcStr = [arr wx_objectAtIndex:0];
            if ([funcStr isEqualToString:@"iOSAppWebTitle"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.customNavigationView updateTitle:[arr wx_objectAtIndex:1]];
                });
                
            }else if ([funcStr isEqualToString:@"closeTitle"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL hidden = [[arr wx_objectAtIndex:1] boolValue];
                    self.customNavigationView.hidden = hidden;
                    [self.webView mas_updateConstraints:^(MASConstraintMaker *make) {
                        make.top.equalTo(hidden ? @(20.0f):@([self navigationHeight]));
                    }];
                    [self.wxContentView layoutIfNeeded];
                });
            }else if ([funcStr isEqualToString:@"closeScrollEvent"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL closed = [[arr wx_objectAtIndex:1] boolValue];
                    self.webView.scrollView.bounces = closed;
                });
            }else if ([funcStr isEqualToString:@"setTitleBar"]) {
                
            }
            
            //埋点
            NSString *eventId = [NSString stringWithFormat:@"jsBridge_jsContext_%@",funcStr];
            [XrsLog postEventId:eventId label:nil attachment:nil];
        }
    }
    else if([message.name isEqualToString:@"xesApp"])
    {
        if (message.body)
        {
            if (![message.body isKindOfClass:[NSString class]])
            {
                return;
            }
            NSDictionary *params = [message.body wx_JSONValue];
            NSString *methodName = [params wx_stringForKey:@"methodName"];
            if (methodName && methodName.length > 0)
            {
                id jsObj = self.jsObjects[@"xesapp"];
                if (jsObj)
                {
                    NSString *funtionName = methodName;
                    SEL selector = NSSelectorFromString([NSString stringWithFormat:@"xesAppHandleJsBridgeRequest_%@", funtionName]);
                    if ([jsObj respondsToSelector:selector])
                    {
                        SuppressPerformSelectorLeakWarning([jsObj performSelector:selector withObject:[params objectForKey:@"params"]]);
                    }
                }
                
                //埋点
                NSString *eventId = [NSString stringWithFormat:@"jsBridge_xesAppHandleJsBridgeRequest_%@",methodName];
                [XrsLog postEventId:eventId label:nil attachment:nil];
            }
        }
    }
    else {
        NSLog(@"message not handle");
    }
}




#pragma wkwebview navigationdelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler API_AVAILABLE(ios(8.0)) {
    
    [WXAnalyticsSDK postSourceInfoWithQuery:navigationAction.request.URL.query];
    
    // 添加日志
    NSString *queryString = navigationAction.request.URL.query;
    NSDictionary *queryDic = [StringValidUtil convertQueryToDic:queryString];
    if (queryDic)
    {
        NSString *xesId = [queryDic wx_stringForKey:@"xesid"];
        NSString *eventId = [queryDic wx_stringForKey:@"eventid"];
        NSString *origin = [queryDic wx_stringForKey:@"origin"];
        
        if (xesId || eventId || origin)
        {
            NSMutableDictionary *params = [NSMutableDictionary dictionary];
            [params wx_setObject:xesId forKey:@"xesid"];
            [params wx_setObject:eventId forKey:@"eventid"];
            [params wx_setObject:origin forKey:@"origin"];
            
            [[WXAnalyticsSDK sharedSDK] addTouchLogData:params];
        }
    }
    
    BOOL status = [self shouldStartLoadWithRequest:navigationAction.request navigationType:navigationAction.navigationType];
    if (status) {
        _navigationType = navigationAction.navigationType;
        decisionHandler(WKNavigationActionPolicyAllow);
    }else {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
    
    if (navigationAction.navigationType == WKNavigationTypeBackForward) {
        [self updateNavigationBar:nil];
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation  API_AVAILABLE(ios(8.0)){
    
    self.startLoadTime = [NSDate wx_getMsecTimeslotString];
    NSString *scheme = webView.URL.scheme;
    NSString *urlStr = webView.URL.absoluteString;
    
// debug模式下如果是http协议则弹出alert
#if ENABLE_DEBUG_MOD
    if ([scheme isEqualToString:@"http"])
    {
        NSLog(@"不安全网页");
        [WXAlertView showWithTitle:@"警告:不安全网页" description:urlStr cancelButtonTitle:@"知道了" otherButtonTitle:@"粘贴" tapBlock:^(NSInteger buttonIndex) {
            if (buttonIndex == 1)
            {
                [PasteboardManager duplicateWithContent:urlStr];
            }
        }];
    }
#endif
    if ([scheme isEqualToString:@"http"])
    {
        NSString *prePageId = [WXBuryManager sharedInstance].prePageId;
        if (![prePageId isKindOfClass:[NSString class]])
        {
            prePageId = @"";
        }
        
        NSString *extraInfo = [NSString stringWithFormat:@"上级页面：%@, 入口网页：%@", prePageId, _urlStr];
        
        [WXAlarmLog alarmEventId:@"http_link_warning" desc:nil content:urlStr extraInfo:extraInfo];
    }
    
    [self setSupportedInterfaceOrientationInfoWithURL:webView.URL];
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    
    if ([self.onlineDelegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.onlineDelegate webViewDidStartLoad:self];
    }
    
//    [self.customNavigationView updateNavigationBarWithNavigationInfo:nil andURL:_webView.URL?_webView.URL.absoluteString:self.urlStr];
    
    if (_navigationType == WKNavigationTypeBackForward) {
        [self updateWebViewLayout];
    }
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation {
    
}


- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    
    [self.webView evaluateJavaScript:@"document.documentElement.style.webkitUserSelect='none'" completionHandler:nil];
    [self.webView evaluateJavaScript:@"document.documentElement.style.webkitTouchCallout='none'" completionHandler:nil];
    
    if (webView.URL.absoluteString.length > 0) {
        self.urlStr = webView.URL.absoluteString;
    }
    
    [self updateNavigationBar:nil];
    
    _progressView.hidden = YES;
    _progressView.progress = 0;
    
    if ([self.onlineDelegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.onlineDelegate webViewDidFinishLoad:self];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error API_AVAILABLE(ios(8.0)){
    if(_onlineDelegate && [_onlineDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]){
        [_onlineDelegate webView:self didFailLoadWithError:error];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error API_AVAILABLE(ios(8.0)){
    NSURL *url = [NSURL URLWithString:[error.userInfo wx_stringForKey:NSErrorFailingURLStringKey]];
    if ([url.absoluteString containsString:@"mailto:"] ||
        [url.absoluteString containsString:@"tel:"] ||
        [url.absoluteString containsString:@"telprompt:"] ||
        [url.absoluteString containsString:@"sms:"]) {
        [[UIApplication sharedApplication] openURL:url];
    }else {
        if(_onlineDelegate && [_onlineDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]){
            [_onlineDelegate webView:self didFailLoadWithError:error];
        }
    }
    
    if (error && ![[WXReachabilityManager sharedInstance] connectionReachable])
    {
        // 无网络提示
        @WeakObj(self);
        [self showErrorViewWithTitle:@"网络异常，请重试" shouldShowBackBtn:YES retryBlock:^{
            NSURL *URL = webView.URL;
            if (URL)
            {
                [selfWeak.webView reload];
            }
            else
            {
                // 首次加载失败时,webview.URL为nil，所以要再次构建request加载
                [selfWeak loadRequest];
            }
        }];
        // 将errorView层级放置自定义导航栏之下
        [self.wxContentView insertSubview:_errorView belowSubview:self.customNavigationView];
    }
    else
    {
        _errorView.hidden = YES;
        if (error && [[WXReachabilityManager sharedInstance] connectionReachable])
        {
            NSString *errorMsg = [error.userInfo objectForKey:NSLocalizedDescriptionKey];
            NSInteger errorCode = error.code;
            [WXAlarmLog alarmEventId:@"h5_loadfail_warning" desc:nil content:webView.URL.absoluteString extraInfo:[NSString stringWithFormat:@"code:%ld, msg:%@", (long)errorCode, errorMsg]];
        }
    }
}

/**web加载可能由于内存问题被挂起 add by cyh*/
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView API_AVAILABLE(macosx(10.11), ios(9.0)){
    
    // 白屏告警
    [WXAlarmLog alarmEventId:@"webview_OOM_warning" desc:nil content:webView.URL.absoluteString extraInfo:nil];
    
    //白屏时，判断当前是否在录音，把录音停止
    [self.xesappWk handleJsBridgeRequest_stopRecord:nil];
    [self.jsBridge stopAllByWebViewCrash];
    @WeakObj(self);
    [self showErrorViewWithTitle:@"内存不足，请手动刷新或更换设备" actionBtnTitles:@[@"退出",@"刷新"] tapBlock:^(NSInteger index) {
        
        [selfWeak hideLoading];
        if (index == 0)
        {
            [selfWeak btnClick];
        }
        else
        {
            // 首次加载失败时,webview.URL为nil，所以要再次构建request加载
            [selfWeak loadRequest];
        }
    }];
}


/**！！！！！！！！！！！！
 一定要确定好要不要加载拦截的页面。
 如果非xueersi域且不需要加载的链接，一定要设置isLoadURL为NO。
 否则会访问到外部域名。
 ！！！！！！！！！！！！！*/
- (BOOL)shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(WKNavigationType)navigationType {
    
    XESLog(@"shouldStartLoadWithRequest === %@, navigationType = %ld",[request.URL host], (long)navigationType);
    
    // 隐藏errorView
    _errorView.hidden = YES;
    
    BOOL isLoadURL = YES;
    NSString *scheme = request.URL.scheme;
    
    NSString *refererStr = nil;
#warning -tmp_leev 需要调整、包括主工程的plist配置 @子龙
    if ([request.URL.host rangeOfString:@"100tal.com"].location != NSNotFound)
    {
        if ([WXAppConfig getAppType] == WXAppTypeQuality)
        {
            refererStr = @"trade.100tal.com://";
        }
        else
        {
            refererStr = @"quality.trade.100tal.com://";
        }
    }
    else if ([request.URL.host rangeOfString:@"xueersi.com"].location != NSNotFound)
    {
        if ([WXAppConfig getAppType] == WXAppTypeQuality)
        {
            refererStr = @"trade.xueersi.com://";
        }
        else
        {
            refererStr = @"quality.trade.xueersi.com://";
        }
    }
    
    if (refererStr)
    {
        self.refererStr = refererStr;
    }
    
    if([[request.URL absoluteString] rangeOfString:@"Lecturelives/app"].location != NSNotFound || [[request.URL absoluteString] rangeOfString:@"Lecturelives/detailH5"].location != NSNotFound) {
        
        //拦截公开讲座和讲座回放(暂时线上还有部分调用量)
        [XrsLog postEventId:@"lecturelive_log" label:nil attachment:nil];

        //先去掉参数
        NSArray * pathAndParams = [[request.URL absoluteString] componentsSeparatedByString:@"?"];
        if(pathAndParams.count > 0){
            
            NSString *lastPath = [[pathAndParams firstObject] lastPathComponent];
            if (lastPath && lastPath.length > 0) {
                
                NSMutableDictionary *params = [NSMutableDictionary dictionary];
                [params wx_setObject:lastPath forKey:@"liveid"];
                
                if(navigationType == WKNavigationTypeLinkActivated)
                {
                    [[XRSJumpCenter sharedInstance] jumpWithPath:@"publiclive/lecturedetail" model:nil param:params];
                }
                else
                {
                    BOOL shouldPop = YES;
                    // 获取query
                    NSString *query = request.URL.query;
                    if (query)
                    {
                        NSDictionary *queryDic = [self parseURLQuery:query];
                        if ([[queryDic wx_numberForKey:@"closeFlag"] intValue] == 1)
                        {
                            shouldPop = NO;
                        }
                    }
                    
                    if (shouldPop)
                    {
                        [[VCManager getNavigationVC] popViewControllerAnimated:NO];
                    }
                    
                    [[XRSJumpCenter sharedInstance] jumpWithPath:@"publiclive/lecturedetail" model:nil param:params];
                }
                isLoadURL = NO;
            }
        }
    }
    else if ([[request.URL host] isEqualToString:@"xescloseweb.com"])
    {
        // 【注】：历史使用xescloseweb.com关闭浏览器逻辑，需要兼容保留
        
        //统一web关闭浏览器的方式
        [[NSNotificationCenter defaultCenter] postNotificationName:kInlineWebDidClosedByH5Notification object:nil];
        
        //刷新学习中心 体验课全局刷新
        if (self.businessType == kWebBusinessType_ExperienceClass)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:kLearnCenterSingleTaskAllRefresh object:nil];
            
        }
        [self closeView];
        isLoadURL = NO;
    }
    else if ([scheme isEqual:[self getschemeFromStr:@"b_m_j_q_b_z_t"]] || [scheme isEqual:[self getschemeFromStr:@"b_m_j_q_b_z"]]||[scheme isEqual:[self getschemeFromStr:@"x_f_j_y_j_o"]] ) {
        // NOTE: 跳转到外部应用(其中小猴、网校1v1等scheme已经在底层做处理了)
        BOOL bSucc = [[UIApplication sharedApplication] openURL:request.URL];
        isLoadURL = !bSucc;
    }
    else if ([self blackListContainsNSURL:request.URL])
    {
        [self showHaveImageNoConentView:self.wxContentView title:@"啊哦！当前应用不支持访问这个页面哟" refreshBlock:NULL];
        [(NoContentView *)_noContentView backBtnShouldShow:YES];
        
        // 添加告警
        [WXAlarmLog alarmEventId:@"url_wh_not_con" desc:@"白名单之外网页访问" content:self.urlStr extraInfo:nil];
        isLoadURL = NO;
    }
    /**！！！！！！！！！！！！
     一定要确定好要不要加载拦截的页面。
     如果非xueersi域且不需要加载的链接，一定要设置isLoadURL为NO。
     否则会访问到外部域名。
     ！！！！！！！！！！！！！*/
    
    return isLoadURL;
}

- (NSString *)getschemeFromStr:(NSString *)str
{
    NSArray *charArray = [str componentsSeparatedByString:@"_"];
    NSString *result = [NSString string];
    for (int i = 0; i < charArray.count; i++)
    {
        const char *cp = [[charArray objectAtIndex:i] cStringUsingEncoding:NSASCIIStringEncoding];
        NSString *cpstr = [NSString stringWithFormat:@"%c", (char)(*cp - 1)];
        result = [result stringByAppendingString:cpstr];
    }
    return result;
}

- (BOOL)allowLoadUrl:(NSURL *)url
{
    BOOL allowLoad = NO;
    
    NSArray *remoteWhiteList = nil;
    NSDictionary *remoteWhiteListDic = [AppConfigManager sharedManager].whiteList;
    if (remoteWhiteListDic
        && [remoteWhiteListDic isKindOfClass:NSDictionary.class])
    {
        remoteWhiteList = [remoteWhiteListDic wx_arrayForKey:@"whitelist"];
    }
    
    if (remoteWhiteList.count == 0 || ![url.scheme hasPrefix:@"http"])
    {
        allowLoad = YES;
    }
    else
    {
        for (NSString *whiteUrl in remoteWhiteList)
        {
            if ([url.host containsString:whiteUrl])
            {
                allowLoad = YES;
                break;;
            }
        }
    }
        
    return allowLoad;
}

- (BOOL)blackListContainsNSURL:(NSURL *)url
{
    BOOL contain = NO;
    NSString *host = url.host;
    
    if (!host)
    {
        return contain;
    }

    NSArray *blackList = [self localBlackList];
    NSDictionary *remoteWhiteListDic = [AppConfigManager sharedManager].whiteList;
    if (remoteWhiteListDic
        && [remoteWhiteListDic isKindOfClass:NSDictionary.class])
    {
        blackList = [remoteWhiteListDic wx_arrayForKey:@"blacklist"];
    }
    
    for (NSString *blackHost in blackList)
    {
        if ([host containsString:blackHost])
        {
            contain = YES;
            break;;
        }
    }
    
    return contain;
}

- (NSArray *)localBlackList
{
    return @[@"baidu.com"];
}

#pragma mark - 工具代码
- (NSDictionary *)parseURLQuery:(NSString *)query
{
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    
    for (NSString *param in [query componentsSeparatedByString:@"&"])
    {
        NSArray *keyValues = [param componentsSeparatedByString:@"="];
        if([keyValues count] < 2)
        {
            continue;
        }
        NSString *value = [keyValues lastObject];
        /**防止value中出现‘=’符号取值不对的情况
         如：url=http://activity.xueersi.com/topic/growth/offline_advertising/?origin=9
         把后面‘=’符号分隔的字符重新拼接起来，还原参数
         */
        if (keyValues.count > 2) {
            NSArray *paramArray = [keyValues subarrayWithRange:NSMakeRange(1, keyValues.count - 1)];
            value = [paramArray componentsJoinedByString:@"="];
        }
        [params setObject:value forKey:[keyValues firstObject]];
    }
    
    return params;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}


#pragma mark - WXShareViewDel

- (WXShareContentObj *)shareContentDataInView:(WXShareView *)shareView shareScene:(WXShareScene)shareScene
{
    return [WXShareContentObj objWithTitle:self.shareTitle
                               contentDesc:self.shareDesc
                                       url:self.shareUrl
                                   context:NSStringFromClass([self class])];
}

- (void)shareView:(WXShareView *)shareView shareToScene:(WXShareScene)shareScene
{
    if (shareScene == WXShareSceneRefreshPage)
    {
        [self xesAppMenuDidPressedRefresh];
    }
    else if (shareScene == WXShareSceneClosePage)
    {
        [self xesAppMenuDidPressedClose];
    }
}

- (BOOL)shouldAutorotate {
    
    return self.overrideShouldAutorotate;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    
    if (_screenType == kWebScreenType_Landscape)
    {
        return  UIInterfaceOrientationMaskLandscape;
    }
    else if (_screenType == kWebScreenType_AllButUpsideDown)
    {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    else
    {
        if ([UIScreen isIpadLand]) {
            return UIInterfaceOrientationMaskLandscape;
        }
        return UIInterfaceOrientationMaskPortrait;
    }
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if ([UIScreen isIpadLand]) {
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        if (orientation == UIInterfaceOrientationLandscapeLeft ||
            orientation == UIInterfaceOrientationLandscapeRight) {
            return orientation;
        }
        return UIInterfaceOrientationLandscapeRight;
    }
    if (_screenType == kWebScreenType_Landscape)
    {
        return UIInterfaceOrientationLandscapeRight;
    }
    return  UIInterfaceOrientationPortrait;
}

#pragma mark - XESAppDelegate

/** 导航栏状态 */
- (void)xesSetWebViewNavigation:(WXWebViewNavigationInfo *)info {
    WXWebViewNavigationBarInfoModel *model = [self.customNavigationView naviagtionInfoModel];
    model.rightButtonIcon = info.action_icon;
    model.rightButtonIconScroll = info.action_icon_scrolled;
    model.title = info.title;
    model.callBackFunc = info.callback;
    model.rightButtonHidden = info.action_icon.length == 0 && info.action_icon_scrolled == 0 && info.callback.length == 0;

    [self updateNavigationBar:model];
}
/** 导航栏高度 */
- (void)xesTransmitNavigationHeight:(NSString *)callback {
    if (callback.length > 0) {
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"%@({'height':%f})",callback,[self navigationHeight]] completionHandler:nil];
    }
}

/** 是否显示标题 */
- (void)setNavTitleVisible:(NSInteger)visible {
    WXWebViewNavigationBarInfoModel *info = [self.customNavigationView naviagtionInfoModel];
    info.hidden = visible != 1;
    [self updateNavigationBar:info];
}

/**设置H5禁止右滑返回事件*/
- (void)setNavPopGesture:(NSInteger)visible  {
    _cancelNavPopGesture = (visible == 0);
    self.navigationController.interactivePopGestureRecognizer.enabled = !_cancelNavPopGesture;
}


/** 改变标题 */
-(void)setNavTitle:(NSString *)title {
    [self.customNavigationView updateTitle:title];
}

/** 显示右侧导航栏按钮 */
- (void)setShareSupport:(NSInteger)support {
    WXWebViewNavigationBarInfoModel *model = [self.customNavigationView naviagtionInfoModel];
    model.rightButtonHidden = support == 0;
    model.rightButtonOption = support;
    [self updateNavigationBar:model];
}

- (void)xesAppMenuDidPressedShare {
    [self.shareView layoutSubviewsWithShareScene:WXShareSceneAll | WXShareSceneRefreshPage | WXShareSceneClosePage];
    [self.shareView showAnimationAddToView:[UIApplication sharedApplication].keyWindow];
    // 埋点
    [XrsBury clickBury:@"click_16_02_003" businessInfo:nil];
}

- (void)xesAppMenuDidPressedRefresh {
    [self refreshBtnPress];
}

- (void)xesAppMenuDidPressedClose {
    [self closeView];
    // 埋点
    [XrsBury clickBury:@"click_16_02_002" businessInfo:nil];
}


/** 返回上一级页面 */
- (void)webClose {
    [self closeView];
}

- (void)xesLogin:(id)params {
    
    if ([[MyUserInfoDefaults sharedDefaults] isLogInStatus]) {
        return;
    }
    
    if ([params isKindOfClass:[NSString class]]) {
        
        self.loginCallBackMethodString  = params;
        [ShareDataManager defaultManager].visitorAdUrl = _orginalUrlStr;
        dispatch_async(dispatch_get_main_queue(), ^{
            [VCManager presentSignInVC];
        });
    }
}

- (void)commentInitApp:(NSDictionary *)params
{
    NSDictionary *h5Dic = [params wx_dictionaryForKey:@"h5"];
    NSDictionary *usedDic = [params wx_dictionaryForKey:@"init"];
    NSString *topicId = [h5Dic wx_stringForKey:@"topicId"];
    NSString *commentId = [h5Dic wx_stringForKey:@"commentId"];
    NSInteger maxLength = [[usedDic wx_numberForKey:@"size"] integerValue];
    NSString *from = [usedDic wx_stringForKey:@"from"];
    
    self.keyBoardViewManager.from = from;
    self.keyBoardViewManager.maxLength = maxLength;
    self.keyBoardViewManager.topicId = topicId;
    self.keyBoardViewManager.commentId = commentId;
}

- (void)commentInvokeKeyboard:(NSDictionary *)params
{
    NSDictionary *h5Dic = [params wx_dictionaryForKey:@"h5"];
    NSDictionary *usedDic = [params wx_dictionaryForKey:@"used"];
    NSString *topicId = [h5Dic wx_stringForKey:@"topicId"];
    NSString *commentId = [h5Dic wx_stringForKey:@"commentId"];
    NSString *from = [usedDic wx_stringForKey:@"from"];
    NSString *businessFrom = [usedDic wx_stringForKey:@"businessFrom"];
    NSString *placeHolder = [usedDic wx_stringForKey:@"placeholder"];
    BOOL isVoice = [[usedDic objectForKey:@"isVoice"] boolValue];
    self.keyBoardViewManager.topicId = topicId;
    self.keyBoardViewManager.commentId = commentId;
    self.keyBoardViewManager.from = from;
    self.keyBoardViewManager.showRecordBtn = ![from isEqualToString:@"complain"];
    self.keyBoardViewManager.placeHolder = placeHolder;
    self.keyBoardViewManager.contentType = [businessFrom integerValue];
    if (isVoice) {
        [self.keyBoardViewManager showAudioView];
    }else {
        [self.keyBoardViewManager showKeyBoard];
    }
    
}

#pragma mark - WXJsBridgeDelegate

- (void)webViewClose {
    [self closeView];
}

- (void)webViewGoBack {
    if (_closedAllWeb || !self.webView.canGoBack) {
        if (self.xesappWk.goBackListenerCallBack) {
            [self.webView evaluateJavaScript:[NSString stringWithFormat:@"%@()", self.xesappWk.goBackListenerCallBack] completionHandler:^(id _Nullable temp, NSError * _Nullable error) {
                self.xesappWk.goBackListenerCallBack = nil;
            }];
            self.xesappWk.goBackListenerCallBack = nil;
        }
        else {
            [self closeView];
        }
    }else{
        [self.webView goBack];
    }
}

- (void)updateNavigationBar:(WXWebViewNavigationBarInfoModel * _Nullable)model {
    [self.customNavigationView updateNavigationBarWithNavigationInfo:model andURL:_webView.URL?_webView.URL.absoluteString:self.urlStr];
    [self updateWebViewLayout];
}

- (WXWebViewNavigationBarInfoModel *)navigationBarInfoModel {
    return [self.customNavigationView naviagtionInfoModel];
}


- (void)basicEventCallbackWithType:(WXBasicEventType)type completion:(void(^)(void))completion{
    
    NSString *jsStr = nil;
    switch (type) {
        case WXBasicEventTypeViewWillAppear:
            jsStr = @"typeof webOnResume === 'function' ? webOnResume() : false;";
            break;
        case WXBasicEventTypeViewWillDisappear:
            jsStr = @"typeof webOnPause === 'function' ? webOnPause() : false;";
            break;
        case WXBasicEventTypeEnterForeground:
            jsStr = @"typeof webOnResume === 'function' ? webOnResume() : false;";
            break;
        case WXBasicEventTypeEnterBackground:
            jsStr = @"typeof webOnPause === 'function' ? webOnPause() : false;";
            break;
        case WXBasicEventTypeLeftButtonClick:
            jsStr = @"typeof wxAppLeftButtonClick === 'function' ? wxAppLeftButtonClick() : false;";
            break;
        case WXBasicEventTypeRightButtonClick:
            jsStr = @"typeof wxAppRightButtonClick === 'function' ? wxAppRightButtonClick() : false;";
            break;
        case WXBasicEventTypeDealloc:
            jsStr = @"typeof webOnDestroy === 'function' ? webOnDestroy() : false;";
            break;
        default:
            break;
    }
    
    if (jsStr.length > 0) {
        [_webView evaluateJavaScript:jsStr completionHandler:^(id _Nullable result, NSError * _Nullable error) {
            if (completion) {
                
                BOOL status = NO;
                if ([result respondsToSelector:@selector(boolValue)]) {
                    status = [result boolValue];
                }
                
                if (status == NO || error != nil) {
                    completion();
                }
            }
        }];
    }else {
        if (completion) {
            completion();
        }
    }
}

- (void)playAdvertVideo:(THJSNativeParam *)param {
    NSString *url = [param.params wx_objectForKey:@"url"];
    NSInteger pauseTime = [[param.params wx_numberForKey:@"pauseTime" defaultValue:@0] integerValue];
    NSString *titleColor = [param.params wx_stringForKey:@"titleColor" defaultValue:@"ffffff"];
    NSString *backgroundColor = [param.params wx_stringForKey:@"backgroundColor" defaultValue:@"333333"];
    NSString *title = [param.params wx_stringForKey:@"title" defaultValue:@"继续播放"];
    
    NSString*filePath = [[WXPreloadMgr sharedInstance] cacheFilePath:url];
    if (filePath.length > 0) {
        self.navigationController.interactivePopGestureRecognizer.enabled = NO;
        self.playerView.pauseTime = pauseTime;
        [self.playerView.bottomButton setTitle:title forState:UIControlStateNormal];
        [self.playerView.bottomButton setTitleColor:[UIColor wx_colorWithHEXString:titleColor] forState:UIControlStateNormal];
        [self.playerView.bottomButton setBackgroundColor:[UIColor wx_colorWithHEXString:backgroundColor]];
        [self.wxContentView addSubview:self.playerView];
        __weak typeof(self) weakSelf = self;
        [self.playerView setPlayFinishBlock:^{
            weakSelf.navigationController.interactivePopGestureRecognizer.enabled = YES;
            if (param.callBackHandler) {
                param.callBackHandler(@{@"status":@1}, nil);
            }
        }];
        self.playerView.pauseTime = [[param.params wx_numberForKey:@"pauseTime" defaultValue:@0] integerValue];
        [self.playerView playWithURL:filePath];
    }else {
        if (param.callBackHandler) {
            THJSBridgeError *error = [[THJSBridgeError alloc] initWithErrorCode:100 message:@"本地尚未缓存成功"];
            param.callBackHandler(@{@"status":@0}, error);
        }
    }
}

- (void)getWebviewRequestParam:(THJSNativeParam *)param {
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSMutableDictionary *common = [NSMutableDictionary dictionary];
    [common wx_setObject:self.startLoadTime forKey:@"loadStartTime"];
    [params wx_setObject:common forKey:@"common"];
    [params wx_setObject:_schemeParams forKey:@"extra"];
    if (param.callBackHandler) {
        param.callBackHandler(params, nil);
    }
    
}

#pragma mark - UIViewControllerTransitioningDelegate
- (nullable id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    self.animation.animationType = WXTransitionAnimationTypePresent;
    return self.animation;
}

- (nullable id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    self.animation.animationType = WXTransitionAnimationTypeDismiss;
    return self.animation;
}

#pragma mark - 埋点

/// 浏览器创建
- (void)postCreateBrowserEvent {
    NSMutableDictionary *parasms = [NSMutableDictionary dictionary];
    [parasms wx_setObject:self.orginalUrlStr forKey:@"orginalUrl"];
    [parasms wx_setObject:self.urlStr forKey:@"url"];
    [parasms wx_setObject:@(self.businessType) forKey:@"businessType"];
    [XrsLog postEventId:@"browser_create" label:@"" attachmentDic:parasms];
}

@end



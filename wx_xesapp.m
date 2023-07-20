//
//  wx_xesapp.m
//  ParentsCommunity
//
//  Created by tianlong on 2018/9/3.
//  Copyright © 2018年 XES. All rights reserved.
//

#import "wx_xesapp.h"
#import "WKScriptMessageInfo.h"

@interface WXJSAnswerResult :NSObject
@property (nonatomic, assign) int stat;
@property (nonatomic,   copy) NSString *msg;
@property (nonatomic, strong) id data;
@end

@implementation WXJSAnswerResult

@end

@implementation wx_xesapp

/** JS会传的答案 */
- (void)showAnswerResult_LiveVideo:(id)obj {
    if ([NSThread isMainThread]) {
        [self showResult:obj];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showResult:obj];
        });
    }
}

- (void)showResult:(id)ret {
    if(self.isWKWebView){
        WKScriptMessageInfo *info = [WKScriptMessageInfo modelWithJSON:ret];
        if ([self.delegate respondsToSelector:@selector(showAnswerResultFromWebView:)]) {
            [self.delegate showAnswerResultFromWebView:info.result];
        }
    }
    else{
        if ([self.delegate respondsToSelector:@selector(showAnswerResultFromWebView:)]) {
            [self.delegate showAnswerResultFromWebView:ret];
        }
    }
    XESLog(@"showAnswerResult_LiveVideo=%@",ret);
}
- (void)onAnswerResult_LiveVideo:(id)obj{
    if ([NSThread isMainThread]) {
        [self showPKResult:obj];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showPKResult:obj];
        });
    }
}
- (void)showPKResult:(id)ret {
    if(self.isWKWebView){
        WKScriptMessageInfo *info = [WKScriptMessageInfo modelWithJSON:ret];
        if ([self.delegate respondsToSelector:@selector(praiseHardQuestionWithRet:)]) {
            [self.delegate praiseHardQuestionWithRet:info.result];
        }
    }
    else{
        if ([self.delegate respondsToSelector:@selector(praiseHardQuestionWithRet:)]) {
            [self.delegate praiseHardQuestionWithRet:ret];
        }
    }    
}

- (void)XesRequestClose:(id)obj{
    if ([NSThread isMainThread]) {
        [self XesRequestCloseAction];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self XesRequestCloseAction];
        });
    }
}

- (void)XesRequestCloseAction{
    XESLog(@"XesRequestCloseAction");
    if ([self.delegate respondsToSelector:@selector(xesRequestCloseSignal)]) {
        [self.delegate xesRequestCloseSignal];
    }
}

#pragma -mark 体验课回调
- (void)showExperienceResult:(id)obj
{
    if ([self.delegate respondsToSelector:@selector(showExperienceResult:)]) {
        [self.delegate showExperienceResult:obj];
    }
    
 XESLog(@"-------here-----1111111--------------%@",obj);
}

//编程课点击了录音
- (void)startAudioRecored:(id)obj{
    if ([NSThread isMainThread]) {
        [self startAudioRecoredAction];
    } else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startAudioRecoredAction];
        });
    }
}
- (void)startAudioRecoredAction{
    if ([self.delegate respondsToSelector:@selector(startAudioRecoredSignal)]) {
        [self.delegate startAudioRecoredSignal];
    }
}
- (void)resetAudioRecored:(id)obj{
    if ([NSThread isMainThread]) {
        [self resetAudioRecoredAction];
    } else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self resetAudioRecoredAction];
        });
    }
}
- (void)resetAudioRecoredAction{
    if ([self.delegate respondsToSelector:@selector(resetAudioRecoredSignal)]) {
        [self.delegate resetAudioRecoredSignal];
    }
}
- (void)stopAudioRecored:(id)obj{
    if ([NSThread isMainThread]) {
        [self stopAudioRecoredAction];
    } else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stopAudioRecoredAction];
        });
    }
}
- (void)stopAudioRecoredAction{
    if ([self.delegate respondsToSelector:@selector(stopAudioRecoredSignal)]) {
        [self.delegate stopAudioRecoredSignal];
    }
}

- (void)playAudioRecored:(id)obj{
    if ([NSThread isMainThread]) {
        [self playAudioRecoredAction];
    } else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playAudioRecoredAction];
        });
    }
}
- (void)playAudioRecoredAction{
    if ([self.delegate respondsToSelector:@selector(playAudioRecoredSignal)]) {
        [self.delegate playAudioRecoredSignal];
    }
}
- (void)startVolumeRecored:(id)obj{
    if ([self.delegate respondsToSelector:@selector(startVolumeSignalWithStopTime:)]) {
        [self.delegate startVolumeSignalWithStopTime:obj];
    }
}
- (void)stopVolumeRecored:(id)obj{
    if ([self.delegate respondsToSelector:@selector(stopVolumeSignal)]) {
        [self.delegate stopVolumeSignal];
    }
}
- (void)getVolumeRecored:(id)obj{
    if ([self.delegate respondsToSelector:@selector(getVolumeSignal)]) {
        [self.delegate getVolumeSignal];
    }
}
@end

//
//  wx_xesapp.h
//  ParentsCommunity
//
//  Created by tianlong on 2018/9/3.
//  Copyright © 2018年 XES. All rights reserved.
//

#import "WXJSObject.h"

@protocol wx_xesappDelegate <JSExport>
/** JS会传的答案 */
- (void)showAnswerResult_LiveVideo:(id)obj;
/** js传递学生答对题目的正确率*/
- (void)onAnswerResult_LiveVideo:(id)obj;
- (void)XesRequestClose:(id)obj;

/*体验课回传答案*/
- (void)showExperienceResult:(id)obj;


//scratch课件开始录音
- (void)startAudioRecored:(id)obj;
- (void)resetAudioRecored:(id)obj;
- (void)stopAudioRecored:(id)obj;
- (void)playAudioRecored:(id)obj;
//响度接口调用
- (void)startVolumeRecored:(id)obj;
- (void)stopVolumeRecored:(id)obj;
- (void)getVolumeRecored:(id)obj;
@end

@protocol LiveArtsDelegate <NSObject>
@optional
- (void)showAnswerResultFromWebView:(id)ret;

@end

@protocol LivePKDelegate <NSObject>

@optional
- (void)praiseHardQuestionWithRet:(id)ret;

@end

@protocol LiveH5SignalDelegate <NSObject>

@optional
- (void)xesRequestCloseSignal;
- (void)startAudioRecoredSignal;
- (void)resetAudioRecoredSignal;
- (void)stopAudioRecoredSignal;
- (void)playAudioRecoredSignal;

/**编程2期 响度需求*/
- (void)startVolumeSignalWithStopTime:(NSDictionary *)stopTimeDict;
- (void)stopVolumeSignal;
- (void)getVolumeSignal;
/*体验课回传答案*/
- (void)showExperienceResult:(NSDictionary *)dict;

@end

@interface wx_xesapp : WXJSObject<wx_xesappDelegate>
- (void)showAnswerResult_LiveVideo:(id)obj;

//战队pk表扬榜需要获取学生课件答对率
- (void)onAnswerResult_LiveVideo:(id)obj;
- (void)XesRequestClose:(id)obj;
//scratch课件开始录音
- (void)startAudioRecored:(id)obj;
- (void)resetAudioRecored:(id)obj;
- (void)stopAudioRecored:(id)obj;
- (void)playAudioRecored:(id)obj;

//响度接口调用
- (void)startVolumeRecored:(id)obj;
- (void)stopVolumeRecored:(id)obj;
- (void)getVolumeRecored:(id)obj;
@end

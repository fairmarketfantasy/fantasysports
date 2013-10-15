//
//  FFBubblePicker.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol FFBubblePickerDelegate

@optional
- (void)bubblePicker:(id)picker didSelectItem:(id)item;
- (void)bubblePickerWillBeginEditing:(id)picker;
- (void)bubblePicker:(id)picker didUpdateText:(NSString *)text;
- (void)bubblePickerDidEndEditing:(id)picker;
- (void)bubblePickerDidUpdateItems:(id)picker;
- (void)bubblePicker:(id)picker willUpdateHeight:(CGFloat)height;

@end


@interface FFBubblePicker : UIView <UITextFieldDelegate>

@property(nonatomic, weak) NSObject<FFBubblePickerDelegate> *delegate;
@property(nonatomic, readonly) NSArray *items;

- (void)addItem:(id)item title:(NSString *)title animated:(BOOL)animated;
- (id)removeItem:(id)item animated:(BOOL)animated;
- (void)clear;
- (void)resetTextView;
- (void)closeAutocomplete;
- (void)openAutocomplete;
- (NSString *)textViewValue;
- (void)setTextViewValue:(NSString *)value;

@end


@interface FFBubblePicker_TextField : UITextField

@end
